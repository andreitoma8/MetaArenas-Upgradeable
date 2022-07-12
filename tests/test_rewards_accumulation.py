from brownie import (
    Contract,
    Metarenas,
    ArenasOld,
    ArenaToken,
    MetaPasses,
    ProxyAdmin,
    TransparentUpgradeableProxy,
    accounts,
    chain,
)
import brownie
from scripts.helpful_scripts import encode_function_data


def test_main():
    # Deloy
    owner = accounts[0]
    # Deploy Proxi Admin
    proxy_admin = ProxyAdmin.deploy({"from": owner})
    arena = ArenaToken.deploy({"from": owner})
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
    # Send ESPORT to Staking SC
    arena.transfer(meta_arenas.address, 100000 * 10**18, {"from": owner})
    for i in [0, 1, 2, 3, 4]:
        # Approve for Burn
        approve_burn_tx = old_arenas.approve(meta_arenas.address, i, {"from": owner})
        # Migrate Arena
        migrate_tx = meta_arenas.migrateArena(i, {"from": owner})
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
    arenas_array = [1, 2, 3, 4, 5]
    # Set rarity for Meta Arenas
    meta_arenas.setRarity(arenas_array, [0, 1, 2, 3, 4], {"from": owner})
    # Assert on-chain rarity
    for i in arenas_array:
        arena_details = meta_arenas.arenaDetails(i)
        assert arena_details[2] == i - 1
    # Stake arenas
    for i in arenas_array:
        meta_arenas.stakeArena(i, {"from": owner})
    # Forward in time one level
    chain.mine(blocks=100, timedelta=259200)
    # Assert accumulation of rewards and level
    for i in arenas_array:
        arena_stake_info = meta_arenas.availableRewards(i, {"from": owner})
        print(arena_stake_info[0] / 10**18)
    # Forward in time to get to level required for Tier 1 upgrade
    chain.mine(blocks=100, timedelta=259200 * 9)
    # Set up arena tier upgrade
    approve_arena = arena.approve(meta_arenas.address, 500 * 10**18, {"from": owner})
    # Assert tier upgrade
    for i in arenas_array:
        upgrade_tier = meta_arenas.upgradeArenaTier(i, {"from": owner})
        arena_details = meta_arenas.arenaDetails(i)
        assert arena_details[0] == 1
        meta_arenas.claimRewards(i, {"from": owner})
    # Forward in time until tier upgrade
    chain.mine(blocks=100, timedelta=259200)
    # Test rewards accumulation after tier upgrade
    for i in arenas_array:
        arena_stake_info = meta_arenas.availableRewards(i, {"from": owner})
        print(arena_stake_info[0] / 10**18)
