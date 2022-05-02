from brownie import (
    MetaArenas,
    ArenasOld,
    EsportToken,
    ByteToken,
    MetaPasses,
    accounts,
    chain,
)


def main():
    # Deloy
    owner = accounts[0]
    byte = ByteToken.deploy({"from": owner})
    esport = EsportToken.deploy({"from": owner})
    passes = MetaPasses.deploy({"from": owner})
    old_arenas = ArenasOld.deploy({"from": owner})
    old_arenas.mint(10, {"from": owner})
    meta_arenas = MetaArenas.deploy(
        old_arenas.address,
        passes.address,
        esport.address,
        byte.address,
        {"from": owner},
    )
    # Approve for Burn
    approve_burn_tx = old_arenas.approve(meta_arenas.address, 1, {"from": owner})
    # Migrate Arena
    migrate_tx = meta_arenas.migrateArena(1, {"from": owner})
    # Stake Arena
    stake_tx = meta_arenas.stakeArena(1, {"from": owner})
    user_arenas_staked = meta_arenas.userStakedArenas(owner.address, {"from": owner})
    print(user_arenas_staked)
    # Forward in time
    chain.mine(blocks=100, timedelta=173000)
    # Assert accumulation of rewards and level
    arena_stake_info = meta_arenas.arenaStakeInfo(1, {"from": owner})
    print(arena_stake_info)
    arena_details = meta_arenas.arenaDetails(1, {"from": owner})
    print(arena_details)
