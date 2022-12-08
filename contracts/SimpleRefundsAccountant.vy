# @version 0.3.7

# INTERFACES #
struct StrategyParams:
    activation: uint256
    last_report: uint256
    current_debt: uint256
    max_debt: uint256

interface IVault:
    def strategies(strategy: address) -> StrategyParams: view
    def balanceOf(addr: address) -> uint256: view
    def maxWithdraw(addr: address) -> uint256: view
    def convertToAssets(shares: uint256) -> uint256: view
    def transfer(receiver: address, amount: uint256) -> bool: nonpayable


# EVENTS #
event ProposeFeeManager:
    fee_manager: address

event AcceptFeeManager:
    fee_manager: address

event UpdatePerformanceFee:
    performance_fee: uint256

event UpdateManagementFee:
    management_fee: uint256

event DistributeRewards:
    rewards: uint256


# STRUCTS #
struct Fee:
    management_fee: uint256
    performance_fee: uint256


# CONSTANTS #
MAX_BPS: constant(uint256) = 10_000
MAX_SHARE: constant(uint256) = 7_500  # 75%

MAX_MF: immutable(uint256)
MAX_PF: immutable(uint256)

# NOTE: A four-century period will be missing 3 of its 100 Julian leap years, leaving 97.
#       So the average year has 365 + 97/400 = 365.2425 days
#       ERROR(Julian): -0.0078
#       ERROR(Gregorian): -0.0003
#       A day = 24 * 60 * 60 sec = 86400 sec
#       365.2425 * 86400 = 31556952.0
SECS_PER_YEAR: constant(uint256) = 31_556_952  # 365.2425 days


# STORAGE #
fee_manager: public(address)
future_fee_manager: public(address)
fees: public(HashMap[address, Fee])


@external
def __init__(max_management_fee: uint256, max_performance_fee: uint256):
    self.fee_manager = msg.sender
    MAX_MF = max_management_fee
    MAX_PF = max_performance_fee

@external
def distribute(vault: address):
    assert msg.sender == self.fee_manager, "not fee manager"
    rewards: uint256 = IVault(vault).balanceOf(self)
    IVault(vault).transfer(msg.sender, rewards)
    log DistributeRewards(rewards)


@external
def set_performance_fee(strategy: address, performance_fee: uint256):
    assert msg.sender == self.fee_manager, "not fee manager"
    assert performance_fee <= self._performance_fee_threshold(), "exceeds performance fee threshold"
    self.fees[strategy].performance_fee = performance_fee
    log UpdatePerformanceFee(performance_fee)


@external
def set_management_fee(strategy: address, management_fee: uint256):
    assert msg.sender == self.fee_manager, "not fee manager"
    assert management_fee <= self._management_fee_threshold(), "exceeds management fee threshold"
    self.fees[strategy].management_fee = management_fee
    log UpdateManagementFee(management_fee)


@external
def propose_fee_manager(_future_fee_manager: address):
    assert msg.sender == self.fee_manager, "not fee manager"
    self.future_fee_manager = _future_fee_manager
    log ProposeFeeManager(_future_fee_manager)


@external
def accept_fee_manager():
    future_fee_manager: address = self.future_fee_manager
    assert msg.sender == future_fee_manager, "not future fee manager"
    self.fee_manager = future_fee_manager
    log AcceptFeeManager(future_fee_manager)


@view
@external
def report(strategy: address, gain: uint256, loss: uint256) -> (uint256, uint256):
    """
    On gains, accountant will compute management and performance fees. They will be cap to a % of gain.
    On losses, accountant will try to compensate with whatever it has
    """

    if gain > 0:
        strategy_params: StrategyParams = IVault(msg.sender).strategies(strategy)
        fee: Fee = self.fees[strategy]
        duration: uint256 = block.timestamp - strategy_params.last_report

        # Compute management_fee
        total_fees: uint256 = (
            strategy_params.current_debt
            * duration
            * fee.management_fee
            / MAX_BPS
            / SECS_PER_YEAR
        )

        # Add performance fees on top of management fees if gains
        total_fees += (gain * fee.performance_fee) / MAX_BPS

        # Cap fee
        maximum_fee: uint256 = (gain * MAX_SHARE) / MAX_BPS

        return (min(total_fees, maximum_fee), 0)

    if loss > 0:
        # Note: Not using maxWithdraw, as that takes only into account liquidity available in the vault
        total_assets: uint256 = IVault(msg.sender).convertToAssets(IVault(msg.sender).balanceOf(self))
        return (0, min(loss, total_assets))

    return (0,0)


@view
@external
def performance_fee_threshold() -> uint256:
    return self._performance_fee_threshold()


@view
@internal
def _performance_fee_threshold() -> uint256:
    return MAX_PF


@view
@external
def management_fee_threshold() -> uint256:
    return self._management_fee_threshold()


@view
@internal
def _management_fee_threshold() -> uint256:
    return MAX_MF