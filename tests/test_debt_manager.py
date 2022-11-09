import pytest
from utils.constants import YEAR

def test_rebalance(
    asset,
    user,
    create_vault,
    create_strategy,
    setup_debt_manager,
    deposit_into_vault,
    gov,
    amount,
    provide_strategy_with_debt,
):
    vault = create_vault(asset)
    strategy1 = create_strategy(vault, int(10**18), int(10**2))
    strategy2 = create_strategy(vault, int(10**18), int(2*10**2))
    vault.add_strategy(strategy1.address, sender=gov)
    vault.add_strategy(strategy2.address, sender=gov)
    new_debt = amount
    deposit_into_vault(vault, 2 * new_debt)
    
    init_strat1_apr = strategy1.aprAfterDebtChange(0)
    init_strat2_apr = strategy2.aprAfterDebtChange(0)

    provide_strategy_with_debt(gov, strategy1, vault, new_debt)
    provide_strategy_with_debt(gov, strategy2, vault, new_debt)

    current_strat1_apr = strategy1.aprAfterDebtChange(0)
    current_strat2_apr = strategy2.aprAfterDebtChange(0)

    assert current_strat1_apr < init_strat1_apr
    assert current_strat2_apr < init_strat2_apr

    debt_manager = setup_debt_manager(vault, [strategy1, strategy2])
    tx_view = debt_manager.estimateAdjustPosition(sender=gov)

    assert tx_view._lowest == 1 # strategy2
    assert tx_view._highest == 0 # strategy1

    vault.update_max_debt_for_strategy(strategy1.address, int(1e18), sender=gov)
    vault.update_max_debt_for_strategy(strategy2.address, int(1e18), sender=gov)

    tx = debt_manager.updateAllocations(sender=gov)
    
    assert strategy1.totalAssets() == amount * 2
    assert strategy2.totalAssets() == 0
