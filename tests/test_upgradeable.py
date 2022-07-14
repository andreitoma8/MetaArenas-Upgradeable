from brownie import (
    Contract,
    Metarenas,
    ArenasOld,
    ArenaTokenMock,
    MetaPasses,
    ProxyAdmin,
    TransparentUpgradeableProxy,
    accounts,
    chain,
)
import brownie
from scripts.helpful_scripts import encode_function_data, upgrade


def test_main():
    # Deloy
    owner = accounts[0]
    # Deploy Proxi Admin
    proxy_admin = ProxyAdmin.deploy({"from": owner})
    arena = ArenaTokenMock.deploy({"from": owner})
    passes = MetaPasses.deploy({"from": owner})
    old_arenas = ArenasOld.deploy({"from": owner})
    old_arenas.mint(10, {"from": owner})
    # Deploy the first MetaArenas implementation
    implementation = Metarenas.deploy({"from": owner})
    # Encode the initializa function
    encoded_initializer_function = encode_function_data(implementation.initialize)
    proxy = TransparentUpgradeableProxy.deploy(
        implementation.address,
        proxy_admin.address,
        encoded_initializer_function,
        {"from": owner},
    )
    # Set Proxy ABI same as Implementation ABI
    meta_arenas = Contract.from_abi("MetaArenas", proxy.address, Metarenas.abi)
    # Set the Address for interfaces in proxy
    meta_arenas.setInterfaces(
        old_arenas.address, passes.address, arena.address, {"from": owner}
    )
    # Approve for Burn
    approve_burn_tx = old_arenas.approve(meta_arenas.address, 0, {"from": owner})
    # Migrate Arena
    migrate_tx = meta_arenas.migrateArena(0, {"from": owner})
    assert meta_arenas.ownerOf(1) == owner.address
    # Assert Arenas 118, 188 and 216 are minted to owner
    assert (
        meta_arenas.ownerOf(118)
        == meta_arenas.ownerOf(188)
        == meta_arenas.ownerOf(216)
        == owner.address
    )
    # Test tokensOfOwner
    tokens_of_owner = meta_arenas.tokensOfOwner(owner.address, {"from": owner})
    print(tokens_of_owner)
    # Stake Arena
    stake_tx = meta_arenas.stakeArena(1, {"from": owner})
    user_arenas_staked = meta_arenas.userStakedArenas(owner.address, {"from": owner})
    assert user_arenas_staked[0] == 1
    print(user_arenas_staked)
    # Assert blocking transfers for staked tokens
    with brownie.reverts():
        meta_arenas.transferFrom(owner.address, accounts[1].address, 1, {"from": owner})
    # Forward in time one level
    chain.mine(blocks=100, timedelta=259200)
    # Assert accumulation of rewards and level
    arena_stake_info = meta_arenas.availableRewards(1, {"from": owner})
    print(arena_stake_info)
    esport_rewards = arena_stake_info[0]
    arena_details = meta_arenas.arenaDetails(1, {"from": owner})
    print(arena_details)
    assert esport_rewards >= ((259200 * 100000) / 3600)
    assert arena_details[1] == 1
    # Forward in time to get to level required for Tier 1 upgrade
    chain.mine(blocks=100, timedelta=259200 * 10)
    # Assert accumulation of rewards and level
    arena_stake_info = meta_arenas.availableRewards(1, {"from": owner})
    print(arena_stake_info)
    esport_rewards = arena_stake_info[0]
    arena_details = meta_arenas.arenaDetails(1, {"from": owner})
    print(arena_details)
    assert esport_rewards >= (((259200 * 10) * 100000) / 3600)
    assert arena_details[1] == 11
    # Set up arena tier upgrade
    approve_esport = arena.approve(meta_arenas.address, 100 * 10**18, {"from": owner})
    # Assert tier upgrade
    upgrade_tier = meta_arenas.upgradeArenaTier(1, {"from": owner})
    arena_details = meta_arenas.arenaDetails(1, {"from": owner})
    assert arena_details[0] == 1
    print(arena_details)
    with brownie.reverts():
        meta_arenas.upgradeArenaTier(1, {"from": owner})
    # Stake another Arena
    approve_burn_tx = old_arenas.approve(meta_arenas.address, 1, {"from": owner})
    migrate_tx = meta_arenas.migrateArena(1, {"from": owner})
    stake_tx = meta_arenas.stakeArena(2, {"from": owner})
    user_arenas_staked = meta_arenas.userStakedArenas(owner.address, {"from": owner})
    assert user_arenas_staked[0] == 1 and user_arenas_staked[1] == 2
    print(user_arenas_staked)
    # Assert unstake Arena
    unstake_arena = meta_arenas.unstakeArena(1, {"from": owner})
    user_arenas_staked = meta_arenas.userStakedArenas(owner.address, {"from": owner})
    print(user_arenas_staked)
    assert len(user_arenas_staked) == 1 and user_arenas_staked[0] == 2
    # Fund Arenas with Tokens
    arena.transfer(meta_arenas.address, 1000 * 10**18, {"from": owner})
    # Assert claim rewards
    balance_esport_before = arena.balanceOf(owner.address, {"from": owner})
    available_rewards = meta_arenas.availableRewards(1, {"from": owner})
    print(available_rewards)
    claim_rewards = meta_arenas.claimRewards(1, {"from": owner})
    rewards = meta_arenas.availableRewards(1, {"from": owner})
    assert rewards[0] < 1000 and rewards[1] < 1000
    balance_esport_after = arena.balanceOf(owner.address, {"from": owner})
    assert balance_esport_after >= balance_esport_before + available_rewards[0]
    # Assert level reset on transfer
    arena_details = meta_arenas.arenaDetails(1, {"from": owner})
    assert arena_details[1] == 11
    print(arena_details)
    transfer_arena = meta_arenas.transferFrom(
        owner.address, accounts[1].address, 1, {"from": owner}
    )
    arena_details = meta_arenas.arenaDetails(1, {"from": owner})
    print(arena_details)
    assert arena_details[1] == 0
    # Assert transfer for unstaked Arena
    assert meta_arenas.ownerOf(1) == accounts[1].address
    # Test if Minting is paused
    meta_arenas.setPaused(False, {"from": owner})
    with brownie.reverts():
        meta_arenas.mint(1, {"from": owner})
    block_timestamp = chain.time()
    print(block_timestamp)
    # Add new district
    meta_arenas.addDistrict({"from": owner})
    # Set minting periods
    meta_arenas.setMintingPeriods(
        block_timestamp,
        block_timestamp + 10000,
        block_timestamp + 20000,
        block_timestamp + 30000,
        {"from": owner},
    )
    # Fund accounts wiht ESPORT token
    arena.mint({"from": accounts[1]})
    arena.mint({"from": accounts[2]})
    arena.mint({"from": accounts[3]})
    # Approve ESPORT
    arena.approve(meta_arenas.address, 1000 * 10**18, {"from": owner})
    arena.approve(meta_arenas.address, 1000 * 10**18, {"from": accounts[1]})
    arena.approve(meta_arenas.address, 1000 * 10**18, {"from": accounts[2]})
    arena.approve(meta_arenas.address, 1000 * 10**18, {"from": accounts[3]})
    # Assert minting only for carbon owners
    print(passes.balanceOf(accounts[1].address, 0))
    with brownie.reverts():
        meta_arenas.mint(1, {"from": accounts[1]})
    passes.mint(0, {"from": accounts[1]})
    passes.mint(1, {"from": accounts[2]})
    passes.mint(2, {"from": accounts[3]})
    # Fund accounts wiht ESPORT token
    arena.mint({"from": accounts[1]})
    arena.mint({"from": accounts[2]})
    arena.mint({"from": accounts[3]})
    arena.mint({"from": accounts[3]})
    meta_arenas.mint(1, {"from": accounts[1]})
    with brownie.reverts():
        meta_arenas.mint(1, {"from": accounts[2]})
        meta_arenas.mint(1, {"from": accounts[3]})
    # Forward to minting for carbon and gold
    chain.mine(blocks=100, timedelta=10000)
    # Assert minting only for carbon and gold owners
    meta_arenas.mint(1, {"from": accounts[1]})
    meta_arenas.mint(1, {"from": accounts[2]})
    # Forward to minting for everyone
    chain.mine(blocks=100, timedelta=9000)
    meta_arenas.mint(1, {"from": accounts[1]})
    meta_arenas.mint(1, {"from": accounts[2]})
    # Assert minting logic
    total_supply = meta_arenas.totalSupply({"from": owner})
    assert total_supply == 10
    owner_of_1001 = meta_arenas.ownerOf(1001, {"from": owner})
    owner_of_1002 = meta_arenas.ownerOf(1002, {"from": owner})
    owner_of_1004 = meta_arenas.ownerOf(1004, {"from": owner})
    assert accounts[1].address == owner_of_1001 == owner_of_1002 == owner_of_1004
    owner_of_1003 = meta_arenas.ownerOf(1003, {"from": owner})
    owner_of_1005 = meta_arenas.ownerOf(1005, {"from": owner})
    assert accounts[2].address == owner_of_1003 == owner_of_1005
    # Forward to minting end
    chain.mine(blocks=100, timedelta=11000)
    # Assert minting end
    with brownie.reverts():
        meta_arenas.mint(1, {"from": accounts[0], "amount": 20 * 10**18})
    # Stake newly minted arena
    with brownie.reverts():
        stake_tx = meta_arenas.stakeArena(1001, {"from": owner})
    stake_tx = meta_arenas.stakeArena(1001, {"from": accounts[1]})
    stake_tx = meta_arenas.stakeArena(1002, {"from": accounts[1]})
    user_arenas_staked = meta_arenas.userStakedArenas(
        accounts[1].address, {"from": owner}
    )
    assert user_arenas_staked[0] == 1001 and user_arenas_staked[1] == 1002
    print(user_arenas_staked)
    # Assert unstake Arena
    with brownie.reverts():
        unstake_arena = meta_arenas.unstakeArena(1001, {"from": owner})
    unstake_arena = meta_arenas.unstakeArena(1001, {"from": accounts[1]})
    user_arenas_staked = meta_arenas.userStakedArenas(
        accounts[1].address, {"from": owner}
    )
    print(user_arenas_staked)
    assert len(user_arenas_staked) == 1 and user_arenas_staked[0] == 1002
    # Assert withdraw
    balance_esport_before = arena.balanceOf(owner.address, {"from": owner})
    meta_arenas.withdraw(10000, 10000, {"from": owner})
    balance_esport_after = arena.balanceOf(owner.address, {"from": owner})
    assert balance_esport_after == balance_esport_before + 10000
    meta_arenas.withdraw(10000, 10000, {"from": owner})
    balance_esport_after = arena.balanceOf(owner.address, {"from": owner})
    assert balance_esport_after == balance_esport_before + 20000
