// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/ Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    address public owner = makeAddr("owner");
    address public user1 = makeAddr("user1");


    function setUp() public {

        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        //(bool success,) = payable(address(vault)).call{value: 1e18}("");
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 rewardAmount) public {
        (bool success,) = payable(address(vault)).call{value: rewardAmount}("");
    }

    function testDepositLinear(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        // 1. deposit
        vm.startPrank(user1);
        vm.deal(user1, amount);
        vault.deposit{value: amount}();
        // 2. check our rebase token balnce
        uint256 startBalance = rebaseToken.balanceOf(user1);
        console.log("startBalance", startBalance);
        assertEq(startBalance, amount);
        // 3. warp the time and check the balance again
        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(user1);
        assertGt(middleBalance, startBalance);
        // 4. earp the time again by the same amount and check the balnce again
        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(user1);
        assertGt(endBalance, middleBalance);

        assertApproxEqAbs(endBalance - middleBalance, middleBalance - startBalance, 1);
        vm.stopPrank();

    }

    function testRedeemStraighAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        vm.startPrank(user1);
        vm.deal(user1, amount);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.balanceOf(user1), amount);
        vault.redeem(type(uint256).max);
        assertEq(rebaseToken.balanceOf(user1), 0);
        assertEq(address(user1).balance, amount);
        vm.stopPrank();
    }

    function testRedeemAfterTimePassed(uint256 depositAmount, uint256 time) public {
        time = bound(time, 1000, type(uint96).max);
        depositAmount = bound(depositAmount, 1e5, type(uint96).max);

        vm.deal(user1, depositAmount);
        vm.prank(user1);
        vault.deposit{value: depositAmount}();
        vm.warp(block.timestamp + time);
        uint256 balanceAfterSomeTime = rebaseToken.balanceOf(user1);
        vm.deal(owner, balanceAfterSomeTime - depositAmount);
        vm.prank(owner);
        addRewardsToVault(balanceAfterSomeTime - depositAmount);
        vm.prank(user1);
        vault.redeem(type(uint256).max);
        uint256 ethBalance = address(user1).balance;
        assertEq(ethBalance, balanceAfterSomeTime);
        assertGt(ethBalance, depositAmount);
        vm.stopPrank();
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5 + 1e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5);

        vm.deal(user1, amount);
        vm.prank(user1);
        vault.deposit{value: amount}();
        
        address user2 = makeAddr("user2");
        uint256 user1Balance = rebaseToken.balanceOf(user1);
        uint256 user2Balance = rebaseToken.balanceOf(user2);
        assertEq(user1Balance, amount);
        assertEq(user2Balance, 0);

        // owner reduces the interest rate
        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        // transfer
        vm.prank(user1);
        rebaseToken.transfer(user2, amountToSend);
        uint256 user1BalanceAfterTransfer = rebaseToken.balanceOf(user1);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);

        assertEq(user1BalanceAfterTransfer, user1Balance - amountToSend);
        assertEq(user2BalanceAfterTransfer, amountToSend);


        // check user interest rate has been inherited (5e10 not 4e10)
        assertEq(rebaseToken.getUserInterestRate(user1), 5e10);
        assertEq(rebaseToken.getUserInterestRate(user2), 5e10);

    }

    function testCannotSetInterestRateByNonOwner(uint256 newInterestRate) public {
        vm.prank(user1);
        vm.expectPartialRevert(bytes4(Ownable.OwnableUnauthorizedAccount.selector));
        rebaseToken.setInterestRate(newInterestRate);
 
    }

    function testCannotCallMintAndBurnByNonOwner() public {
        vm.prank(user1);
        vm.expectPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
        rebaseToken.mint(user1, 100, rebaseToken.getUserInterestRate(user1));
        vm.expectPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
        rebaseToken.burn(user1, 100);
    }

    function testgetPrincipleAmount(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        vm.deal(user1, amount);
        vm.prank(user1);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.principleBalanceOf(user1), amount);

        vm.warp(block.timestamp + 1 hours);
        assertEq(rebaseToken.principleBalanceOf(user1), amount);
    }

    function testGetRebaseTokenAddress() public view {
        assertEq(vault.getRebaseTokenAddress(), address(rebaseToken));
    }

    function testInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(newInterestRate, initialInterestRate, type(uint96).max);
        vm.prank(owner);
        vm.expectPartialRevert(bytes4(RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector));
        rebaseToken.setInterestRate(newInterestRate);
        assertEq(rebaseToken.getInterestRate(), initialInterestRate);
    }
}