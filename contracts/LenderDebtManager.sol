// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.14;

import "./interfaces/IVault.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILenderStrategy {
    function aprAfterDebtChange(
        int256 _delta
    ) external view returns (uint256 _apr);
}

contract LenderDebtManager {
    IVault public immutable vault;
    IERC20 public immutable asset;
    address[] public strategies;

    uint256 public lastBlockUpdate;

    constructor(IVault _vault) {
        vault = _vault;
        asset = IERC20(_vault.asset());
        lastBlockUpdate = block.timestamp;
    }

    function addStrategy(address _strategy /* onlyAuthorized */) external {
        require(vault.strategies(_strategy).activation != 0);

        for (uint256 i = 0; i < strategies.length; ++i) {
            if (strategies[i] == _strategy) return;
        }

        strategies.push(_strategy);
    }

    // TODO: Permissionless remove when not in vault, permissioned when in vault
    function removeStrategy(address _strategy /* onlyAuthorized */) external {
        uint256 strategyCount = strategies.length;
        for (uint256 i = 0; i < strategyCount; ++i) {
            if (strategies[i] == _strategy) {
                // if not last element
                if (i != strategyCount - 1) {
                    strategies[i] = strategies[strategyCount - 1];
                }
                strategies.pop();
                return;
            }
        }
    }

    function updateAllocations() public {
        (
            uint256 _lowest,
            uint256 _lowestApr,
            uint256 _highest,
            uint256 _potential
        ) = estimateAdjustPosition();

        // only pull out if we can do better
        if (_potential > _lowestApr) {
            address _lowestStrategy = strategies[_lowest];

            // harvest all profits
            vault.tend_strategy(_lowestStrategy);

            // report to the vault so it doesnt leave anything behind
            vault.process_report(_lowestStrategy);

            // update the debt down to 0
            vault.update_debt(_lowestStrategy, 0);
        }

        uint256 _totalIdle = vault.total_idle();

        // deposit all thats possible
        if (_totalIdle > 0) {
            address _highestStrategy = strategies[_highest];
            uint256 _highestCurrentDebt = vault
                .strategies(_highestStrategy)
                .current_debt;

            vault.update_debt(
                _highestStrategy,
                _totalIdle + _highestCurrentDebt
            );

            lastBlockUpdate = block.timestamp;
        }
    }

    //estimates highest and lowest apr lenders. Public for debugging purposes but not much use to general public
    function estimateAdjustPosition()
        public
        view
        returns (
            uint256 _lowest,
            uint256 _lowestApr,
            uint256 _highest,
            uint256 _potential
        )
    {
        // cache array to save storage loads
        address[] memory _strategies = strategies;

        uint256 strategyCount = _strategies.length;
        if (strategyCount == 0) {
            return (0, type(uint256).max, 0, 0);
        }

        if (strategyCount == 1) {
            ILenderStrategy _strategy = ILenderStrategy(_strategies[0]);
            uint256 apr = _strategy.aprAfterDebtChange(int256(0));
            return (0, apr, 0, apr);
        }

        //all loose assets are to be invested
        uint256 looseAssets = vault.total_idle();

        // our simple algo
        // get the lowest apr strat
        // cycle through and see who could take its funds plus want for the highest apr
        _lowestApr = type(uint256).max;
        _lowest = 0;
        uint256 lowestNav = 0;
        for (uint256 i; i < strategyCount; ++i) {
            ILenderStrategy _strategy = ILenderStrategy(_strategies[i]);
            uint256 _strategyNav = vault
                .strategies(address(_strategy))
                .current_debt;
            if (_strategyNav > 0) {
                uint256 apr = _strategy.aprAfterDebtChange(int256(0));
                if (apr < _lowestApr) {
                    _lowestApr = apr;
                    _lowest = i;
                    lowestNav = _strategyNav;
                }
            }
        }

        uint256 toAdd = lowestNav + looseAssets;

        uint256 highestApr = 0;
        _highest = 0;
        for (uint256 i; i < strategyCount; ++i) {
            ILenderStrategy _strategy = ILenderStrategy(_strategies[i]);
            uint256 apr = _strategy.aprAfterDebtChange(int256(looseAssets));

            if (apr > highestApr) {
                highestApr = apr;
                _highest = i;
            }
        }
        _potential = ILenderStrategy(_strategies[_highest]).aprAfterDebtChange(
            int256(toAdd)
        );
    }

    // External function get the full array of strategies
    function getStrategies() external view returns (address[] memory) {
        return strategies;
    }
}
