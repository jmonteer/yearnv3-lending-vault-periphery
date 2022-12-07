// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.14;

import "../interfaces/IVault.sol";
import "./BaseStrategy.sol";

contract MockStrategy is BaseStrategy {
    uint256 public base;
    uint256 public slope;
    uint256 constant MAX_BPS = 10_000;

    constructor(
        address _vault,
        string memory _name,
        uint256 _base,
        uint256 _slope
    ) BaseStrategy(_vault, _name) {
        base = _base;
        slope = _slope;
    }

    function aprAfterDebtChange(int256 delta) external view returns (uint256) {
        return base - (slope * (_totalAssets() + uint256(delta))) / MAX_BPS;
    }

    function _maxWithdraw(
        address owner
    ) internal view override returns (uint256) {
        return _totalAssets();
    }

    function _freeFunds(
        uint256 _amount
    ) internal returns (uint256 _amountFreed) {
        _amountFreed = balanceOfAsset();
    }

    function _withdraw(
        uint256 amount,
        address receiver,
        address owner
    ) internal override returns (uint256) {
        return _freeFunds(amount);
    }

    function _totalAssets() internal view override returns (uint256) {
        return balanceOfAsset();
    }

    function _invest() internal override {}

    function _withdrawFromComet(uint256 _amount) internal {}

    function balanceOfAsset() internal view returns (uint256) {
        return IERC20(asset).balanceOf(address(this));
    }
}
