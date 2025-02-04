// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";


contract Vault {
    // we need to pass the token address to the computer.
    // create a deposit function that mints token to the user equal to the amount of ETH sent.
    // create a redeem function that burns token from the user and sends the user ETH.
    // create a way to add rewards to the vault. 

    IRebaseToken private immutable i_rebaseToken;

    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    error VAULT__RedeemFailed();

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    receive() external payable {}


    /**
     * @notice Allows users to Deposit ETH into the vault and mint rebase tokens in return
     */
    function deposit() external payable {
        // 1. use the amount of ETH the user has sent to mint token to the user
        uint256 interestRate = i_rebaseToken.getInterestRate();
        i_rebaseToken.mint(msg.sender, msg.value, interestRate);
        emit Deposit(msg.sender, msg.value);
    }


    /**
     * 
     * @param _amount The amount of tokens to redeem
     * @notice Allows users to redeem tokens from the vault and send ETH in return
     */
    function redeem(uint256 _amount) external {
        if(_amount == type(uint256).max) {
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }
        // 1. use the amount of token the user has to burn and send the user ETH
        i_rebaseToken.burn(msg.sender, _amount);
        //payable(msg.sender).transfer(_amount);
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert VAULT__RedeemFailed();
        }
        emit Redeem(msg.sender, _amount);
    }


    /**
     * @notice Get the address of the rebase token
     * @return The address of the rebase token
     */
    function getRebaseTokenAddress() external view returns (address) { 
        return address(i_rebaseToken);
    }
}