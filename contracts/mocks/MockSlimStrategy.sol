// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Minimum version of strategy to make tests work
contract MockSlimStrategy {
    address public asset;
    address public vault;

    constructor(address asset_, address vault_) {
        asset = asset_;
        vault = vault_;
    }

    function maxDeposit(address) public view returns (uint256) {
        return 2 ** 256 - 1;
    }

    function deposit(
        uint256 assets,
        address receiver
    ) public returns (uint256) {
        require(msg.sender == vault && msg.sender == receiver, "not owner");
        IERC20(asset).transferFrom(vault, address(this), assets);
        return assets;
    }
}
