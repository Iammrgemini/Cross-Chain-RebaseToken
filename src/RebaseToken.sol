// SPDX-License-Identifier: MIT

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions
pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title RebaseToken
 * @author Wisdom Uche Ijika
 * @notice This is a cross-chain rebase token that incentivises users to deposit into a vault and gain interests and rewards.
 * @notice The interest rate in the smart contract can only decrease over time.
 * @notice Each users will have their own interest rate that is the global interest rate at the time of depositing.
 *
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    ////////////////////////////////
    ////       errors          ////
    //////////////////////////////
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    ////////////////////////////////
    ////       state varables  ////
    //////////////////////////////
    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    uint256 private s_interestRate = (5 * PRECISION_FACTOR) / 1e8;
    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;

    ////////////////////////////////
    ////       events          ////
    //////////////////////////////
    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender){}


    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @notice Set the interest rate in the contract
     * @param _newInterestRate The new interest rate to set
     * @dev The interest rate can only decrease
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner{
        // Set the interest rate
        if (_newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    /**
     * @notice Get the principle balance of a user. This is the number of tokens that have currently been minted to the user not
       including any interest that has occured since the last time user interected with the protocol
     * @param _user The address of the user
     * @return The principle balance of the user
     */
    function principleBalanceOf(address _user) public view returns (uint256) {
        return super.balanceOf(_user);
    }


    /**
     * @notice Mint the user token when they deposit into the vault
     * @param _to  The address of the user
     * @param _amount The amount of tokens to mint
     */
    function mint(address _to, uint256 _amount, uint256 _userInterestRate) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = _userInterestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Burn the user token when they withdraw from the vault
     * @param _from The address of the user
     * @param _amount The amount of tokens to burn
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    function balanceOf (address _user) public view override returns (uint256) {
        // get the current principle balance of the user (the number of tokens that have been minted to the user)
        // multiply the principle balance by the interest rate that has accumulated in the time since the last update
        return super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user) / PRECISION_FACTOR;

    }

    /**
     * @notice Transfer token from one user to the other
     * @param _recipient The address of the recipient
     * @param _amount The amount of tokens to transfer
     * @return True if the transfer was successful
     */

    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        if(_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }


    /**
     * @notice Transfer token from one user to the other
     * @param _sender The address of the sender
     * @param _recipient  The address of the recipient
     * @param _amount The amount of tokens to transfer
     * @return True if the transfer was successful
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        if(_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user) internal view returns (uint256 linearInterest) {
        // we need to calculate the interest thatbhas accumulated since the last update
        // this is going to be linear growth with time
        // 1. calculate the time since the last update
        // 2. calculate the amount of interest that has accumulated since the last update
        // 3. calculate the amount of linear growth
        //(principle amount) + (principle amount * interest rate * time elapsed)
        // deposit: 10 tokens
        // interest rate 0.5 tokens per second
        // time elapsed is 2 seconds
        // 10 + (10 * 0.5 * 2) = 25 tokens

        uint256 timeElapsed  = block.timestamp - s_userLastUpdatedTimestamp[_user];
        linearInterest =( PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed));
    }


    /**
     * 
     * @param _user The user to mint accrued interest to
     * @notice mint accrued interest to the user since the last time they interacted with the protocol (e.g.. burn,mint, transfer)
     * @dev This function should be called after every interaction with the protocol
     */
    function _mintAccruedInterest(address _user) internal {
        // 1. find their current balance of the rebase tokens that have been minted to the user.  --> principle balance
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        // 2. calculate their current balance including any interest. --> balanceOf
        uint256 currentBalance = balanceOf(_user);
        // 3. calculate the number of tokens that need to be minted to the user --> (2) - (1)
        uint256 balanceIncrease = currentBalance - previousPrincipleBalance;
        // 5. set the user last updated timestamp
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
        // 4. call _mint to mint the tokens to the user
        _mint(_user, balanceIncrease);
    }

    /**
     * 
     * @notice Get the interest rate of the protocol
     * @return The interest rate of the protocol
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    /**
     * 
     * @notice Get the interest rate of a user
     * @param _user The user to get the interest rate of
     * @return The interest rate of the user
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }
}
