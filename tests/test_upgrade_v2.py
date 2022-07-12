from brownie import (
    Contract,
    Metarenas,
    MetaArenasV2,
    ArenasOld,
    ArenaToken,
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
    # Set interfaces
    meta_arenas.setInterfaces(
        old_arenas.address, passes.address, arena.address, {"from": owner}
    )
    # Approve for Burn
    approve_burn_tx = old_arenas.approve(meta_arenas.address, 0, {"from": owner})
    # Assert Migrate Arena 1
    migrate_tx = meta_arenas.migrateArena(0, {"from": owner})
    assert meta_arenas.ownerOf(1) == owner.address
    # Deploy Arenas V2
    implementation2 = MetaArenasV2.deploy({"from": owner})
    # Upgrade
    upgrade(owner, proxy, implementation2, proxy_admin)
    # Set Proxy ABI same as Implementation ABI
    meta_arenas = Contract.from_abi("MetaArenas", proxy.address, MetaArenasV2.abi)
    # Approve for Burn
    approve_burn_tx = old_arenas.approve(meta_arenas.address, 1, {"from": owner})
    # Assert migrate Arena 2 in V2
    migrate_tx = meta_arenas.migrateArena(1, {"from": owner})
    assert meta_arenas.ownerOf(2) == owner.address
    print(meta_arenas.test())
