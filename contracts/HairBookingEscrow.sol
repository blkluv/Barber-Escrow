//SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "../interfaces/IERC20.sol";
import "../interfaces/ILendingPool.sol";

contract HairBookingEscrow {
    address barber;
    address arbiter;

    uint256[] bookingID;
    mapping(uint256 => bool) bookingExists;
    mapping(uint256 => uint256) bookingIDToAmount;
    mapping(uint256 => address) bookingIDToCustomer;

    mapping(uint256 => mapping(address => uint256)) bookingIDToCustomerToAmount;

    mapping(address => uint256) cutomersToNumberOfBookings; // can give a discount after X amount of bookings
    address[] allPreviousCustomers;

    // mainnet AAVE v2 lending pool
    ILendingPool pool =
        ILendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    // aave interest bearing DAI
    IERC20 aDai = IERC20(0x028171bCA77440897B824Ca71D1c56caC55b68A3);
    // DAI stablecoin
    IERC20 dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    event bookingMade(
        address indexed customer,
        uint256 bookingAmount,
        uint256 bookingNumber
    );
    event bookingCancelled(address indexed canceller, uint256 bookingID);
    event paymentReceived(uint256);
    event paidInterestToCustomer(uint256);

    constructor(address _barber, address _arbiter) {
        barber = _barber;
        arbiter = _arbiter;
    }

    function bookHairCut(uint256 _bookingAmount) external {
        // adding 1 to the total number of bookings this customer has made
        cutomersToNumberOfBookings[msg.sender] += 1;

        uint256 newBooking = bookingID.length + 1;
        // adding the booking ID to the booking ID array
        bookingID.push(newBooking);
        // adding the booking to the mapping of bookings that exist
        bookingExists[newBooking] = true;
        // tying this bookingID to the amount
        bookingIDToAmount[newBooking] = _bookingAmount;
        // tying this bookingID to the customer
        bookingIDToCustomer[newBooking] = msg.sender;

        //transferring the booking amount of dai to this contract
        dai.transferFrom(msg.sender, address(this), _bookingAmount);

        // depositing the dai into aave
        dai.approve(address(pool), _bookingAmount);
        pool.deposit(address(dai), _bookingAmount, address(this), 0);

        emit bookingMade(
            msg.sender,
            _bookingAmount,
            cutomersToNumberOfBookings[msg.sender]
        );
    }

    //once the haircut is complete, the arbiter will confirm it with this function
    function completed(uint256 _bookingID) external {
        require(msg.sender == arbiter, "You are not the arbiter.");

        address customer = bookingIDToCustomer[_bookingID];

        // calculating the amount of interest earned on aave
        uint256 totalBalance = aDai.balanceOf(address(this));

        // calculation: giving the barber the intital deposit and 50% of the extra interest
        uint256 amountForBarber = bookingIDToAmount[_bookingID] +
            ((totalBalance - bookingIDToAmount[_bookingID]) / 2);

        // calculation: giving the customer the other 50% of the extra interest
        uint256 interestForCustomer = (totalBalance -
            bookingIDToAmount[_bookingID]) / 2;

        // withdrawing the initial deposit + the interest from aave
        pool.withdraw(address(dai), type(uint256).max, address(this));

        // tranferring interest to the customer
        payable(customer).transfer(interestForCustomer);
        emit paidInterestToCustomer(interestForCustomer);

        // transferring the initial deposit + the remaining interest to the barber
        payable(barber).transfer(amountForBarber);
        emit paymentReceived(amountForBarber);
    }

    // function to cancel the booking
    function cancelBooking(uint256 _bookingID) public {
        require(
            bookingIDToCustomer[_bookingID] == msg.sender ||
                msg.sender == barber,
            "You are not permitted to cancel this booking."
        );
        require(bookingExists[_bookingID], "Booking does not exist");

        // marking the booking as no longer existing
        bookingExists[_bookingID] = false;

        // calculating the amount of interest earned on aave
        uint256 totalBalance = aDai.balanceOf(address(this));

        uint256 amountForBarber = totalBalance - bookingIDToAmount[_bookingID];
        uint256 amountForCustomer = bookingIDToAmount[_bookingID];

        //withdrawing the customer's deposit from aave
        pool.withdraw(address(dai), type(uint256).max, address(this));

        address customer = bookingIDToCustomer[_bookingID];
        // transferring the customer's initial deposit back to them
        payable(customer).transfer(amountForCustomer);

        // transferring the interest earned back to the barber
        payable(barber).transfer(amountForBarber);

        emit bookingCancelled(msg.sender, _bookingID);
    }
}