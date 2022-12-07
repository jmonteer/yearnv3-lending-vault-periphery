import pytest
from ape import Contract, accounts, project
from utils.constants import MAX_INT, ROLES

# this should be the address of the ERC-20 used by the strategy/vault
ASSET_ADDRESS = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"  # USDC
ASSET_WHALE_ADDRESS = "0x0A59649758aa4d66E25f08Dd01271e891fe52199"  # USDC WHALE


@pytest.fixture(scope="session")
def gov(accounts):
    # TODO: can be changed to actual governance
    return accounts[0]


@pytest.fixture(scope="session")
def strategist(accounts):
    return accounts[1]


@pytest.fixture(scope="session")
def user(accounts):
    return accounts[9]


@pytest.fixture(scope="session")
def fee_manager(accounts):
    return accounts[2]


@pytest.fixture(scope="session")
def asset():
    yield Contract(ASSET_ADDRESS)


@pytest.fixture(scope="session")
def whale():
    yield Contract(ASSET_WHALE_ADDRESS)


@pytest.fixture(scope="session")
def amount(asset):
    # Use 1M
    return 1_000_000 * 10 ** asset.decimals()


@pytest.fixture(scope="session")
def create_vault(project, gov):
    def create_vault(asset, governance=gov, deposit_limit=MAX_INT, fee_manager=None):
        vault = gov.deploy(
            project.dependencies["yearn-vaults"]["master"].VaultV3,
            asset,
            "VaultV3",
            "AV",
            governance,
            0,
        )

        vault.set_role(
            gov.address,
            ROLES.STRATEGY_MANAGER | ROLES.DEBT_MANAGER | ROLES.ACCOUNTING_MANAGER,
            sender=gov,
        )
        # set vault deposit
        vault.set_deposit_limit(deposit_limit, sender=gov)

        # set up fee manager
        if fee_manager:
            vault.set_accountant(fee_manager.address, sender=gov)

        return vault

    yield create_vault


@pytest.fixture(scope="function")
def vault(gov, asset, create_vault):
    vault = create_vault(asset)
    yield vault


@pytest.fixture
def create_strategy(project, strategist):
    def create_strategy(vault, base, slope):
        strategy = strategist.deploy(project.MockStrategy, vault, "strat", base, slope)
        return strategy

    yield create_strategy


@pytest.fixture(scope="function")
def create_mock_strategy(project, gov, asset):
    def create_mock_strategy(vault):
        return gov.deploy(project.MockStrategy, asset.address, vault.address)

    yield create_mock_strategy


@pytest.fixture
def create_simple_accountant(project, fee_manager):
    def create_simple_accountant(
        max_management_fee: int = 1_000, max_performance_fee: int = 1_000
    ):
        return fee_manager.deploy(
            project.SimpleAccountant, max_management_fee, max_performance_fee
        )

    yield create_simple_accountant


@pytest.fixture(scope="function")
def simple_accountant(create_simple_accountant):
    yield create_simple_accountant()


@pytest.fixture
def setup_debt_manager(project, gov):
    def setup_debt_manager(vault, strategies):
        debt_manager = gov.deploy(project.LenderDebtManager, vault)

        vault.set_role(
            debt_manager.address,
            ROLES.DEBT_MANAGER,
            sender=gov,
        )

        for s in strategies:
            if vault.strategies(s).activation == 0:
                print("STRATEGY", s.address, "NOT ADDED")
                continue
            debt_manager.addStrategy(s, sender=gov)

        return debt_manager

    yield setup_debt_manager


@pytest.fixture(scope="function")
def strategy(vault, create_strategy):
    strategy = create_strategy(vault)
    yield strategy


@pytest.fixture(scope="function")
def create_vault_and_strategy(strategy, vault, deposit_into_vault):
    def create_vault_and_strategy(account, amount_into_vault):
        deposit_into_vault(vault, amount_into_vault)
        vault.add_strategy(strategy.address, sender=account)
        return vault, strategy

    yield create_vault_and_strategy


@pytest.fixture(scope="function")
def deposit_into_vault(asset, gov):
    def deposit_into_vault(vault, amount_to_deposit):
        whale = accounts[ASSET_WHALE_ADDRESS]
        asset.approve(vault.address, amount_to_deposit, sender=whale)
        vault.deposit(amount_to_deposit, whale.address, sender=whale)

    yield deposit_into_vault


@pytest.fixture(scope="session")
def user_deposit(asset):
    def user_deposit(user, vault, amount):
        initial_balance = asset.balanceOf(vault)
        if asset.allowance(user, vault) < amount:
            asset.approve(vault.address, MAX_INT, sender=user)
        vault.deposit(amount, user.address, sender=user)
        assert asset.balanceOf(vault) == initial_balance + amount

    return user_deposit


@pytest.fixture(scope="function")
def provide_strategy_with_debt():
    def provide_strategy_with_debt(account, strategy, vault, target_debt: int):
        vault.update_max_debt_for_strategy(
            strategy.address, target_debt, sender=account
        )
        vault.update_debt(strategy.address, target_debt, sender=account)

    return provide_strategy_with_debt


@pytest.fixture
def user_interaction(strategy, vault, deposit_into_vault):
    def user_interaction():
        return

    yield user_interaction
