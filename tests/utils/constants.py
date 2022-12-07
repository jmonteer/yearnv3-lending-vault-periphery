from enum import IntFlag

DAY = 86400
WEEK = 7 * DAY
YEAR = 365 * 24 * 3600
MAX_INT = 2**256 - 1
ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"

REL_ERROR = 1e-3

MAX_BPS = 10_000


class ROLES(IntFlag):
    STRATEGY_MANAGER = 1
    DEBT_MANAGER = 2
    EMERGENCY_MANAGER = 4
    ACCOUNTING_MANAGER = 8
