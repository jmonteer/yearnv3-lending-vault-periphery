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

    address public owner;

    modifier onlyAuthorized() {
        checkAuthorized();
        _;
    }

    function checkAuthorized() internal view {
        require(owner == msg.sender, "!authorized");
    }

    constructor(IVault _vault) {
        vault = _vault;
        asset = IERC20(_vault.asset());
        lastBlockUpdate = block.timestamp;

        owner = msg.sender;
    }

    function addStrategy(address _strategy) external onlyAuthorized {
        require(vault.strategies(_strategy).activation != 0);

        for (uint256 i = 0; i < strategies.length; ++i) {
            if (strategies[i] == _strategy) return;
        }

        strategies.push(_strategy);
    }

    // Permissionless remove when not in vault, permissioned when in vault
    function removeStrategy(address _strategy) external {
        if (vault.strategies(_strategy).activation != 0) {
            checkAuthorized();
        }

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
            address _lowest,
            uint256 _lowestApr,
            address _highest,
            uint256 _potential
        ) = estimateAdjustPosition();

        // only pull out if we can do better
        if (_potential > _lowestApr) {
            // harvest all profits
            vault.tend_strategy(_lowest);

            // report to the vault so it doesnt leave anything behind
            vault.process_report(_lowest);

            // update the debt down to 0
            vault.update_debt(_lowest, 0);
        }

        uint256 _totalIdle = vault.total_idle();

        // deposit all thats possible
        if (_totalIdle > 0) {
            uint256 _highestCurrentDebt = vault
                .strategies(_highest)
                .current_debt;

            vault.update_debt(_highest, _totalIdle + _highestCurrentDebt);

            lastBlockUpdate = block.timestamp;
        }
    }

    //estimates highest and lowest apr lenders. Public for debugging purposes but not much use to general public
    function estimateAdjustPosition()
        public
        view
        returns (
            address _lowest,
            uint256 _lowestApr,
            address _highest,
            uint256 _potential
        )
    {
        // cache array to save storage loads
        address[] memory _strategies = strategies;

        uint256 strategyCount = _strategies.length;
        if (strategyCount == 0) {
            return (address(0), type(uint256).max, address(0), 0);
        }

        if (strategyCount == 1) {
            ILenderStrategy _strategy = ILenderStrategy(_strategies[0]);
            uint256 apr = _strategy.aprAfterDebtChange(int256(0));
            return (address(_strategy), apr, address(_strategy), apr);
        }

        //all loose assets are to be invested
        uint256 looseAssets = vault.total_idle();

        // our simple algo
        // get the lowest apr strat
        // cycle through and see who could take its funds plus want for the highest apr
        _lowestApr = type(uint256).max;
        _lowest;
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
                    _lowest = address(_strategy);
                    lowestNav = _strategyNav;
                }
            }
        }

        uint256 toAdd = lowestNav + looseAssets;

        uint256 highestApr = 0;
        _highest;
        for (uint256 i; i < strategyCount; ++i) {
            ILenderStrategy _strategy = ILenderStrategy(_strategies[i]);
            uint256 apr = _strategy.aprAfterDebtChange(int256(looseAssets));

            if (apr > highestApr) {
                highestApr = apr;
                _highest = address(_strategy);
            }
        }
        _potential = ILenderStrategy(_highest).aprAfterDebtChange(
            int256(toAdd)
        );
    }

    // External function get the full array of strategies
    function getStrategies() external view returns (address[] memory) {
        return strategies;
    }

    function _processReport(address _strategy, bool _tend) internal {
        if (_tend) {
            vault.tend_strategy(_strategy);
        }

        vault.process_report(_strategy);
    }

    function processReport(address _strategy) external onlyAuthorized {
        require(vault.strategies(_strategy).activation != 0, "not active");
        _processReport(_strategy, false);
    }

    function tendAndReport(address _strategy) external onlyAuthorized {
        require(vault.strategies(_strategy).activation != 0, "not active");
        _processReport(_strategy, true);
    }

    function tendStrategy(address _strategy) external onlyAuthorized {
        require(vault.strategies(_strategy).activation != 0, "not active");
        vault.tend_strategy(_strategy);
    }
}
