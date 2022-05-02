from brownie import (
    Contract,
    MetaArenas,
    ArenasOld,
    EsportToken,
    ByteToken,
    MetaPasses,
    ProxyAdmin,
    TransparentUpgradeableProxy,
    accounts,
    config,
)
from scripts.helpful_scripts import encode_function_data, upgrade


def main():
    # Deloy
    owner = accounts.add(config["wallets"]["from_key"])
    # Deploy Proxi Admin
    proxy_admin = ProxyAdmin.deploy({"from": owner})
    byte = ByteToken.deploy({"from": owner})
    esport = EsportToken.deploy({"from": owner})
    passes = MetaPasses.deploy({"from": owner})
    old_arenas = ArenasOld.deploy({"from": owner})
    old_arenas.mint(10, {"from": owner})
    # Deploy the first MetaArenas implementation
    implementation = MetaArenas.deploy(
        {"from": owner},
    )
    # Encode the initializa function
    encoded_initializer_function = encode_function_data(implementation.initialize)
    proxy = TransparentUpgradeableProxy.deploy(
        implementation.address,
        proxy_admin.address,
        encoded_initializer_function,
        {"from": owner},
    )
    # Set Proxy ABI same as Implementation ABI
    meta_arenas = Contract.from_abi("MetaArenas", proxy.address, MetaArenas.abi)
    # Set the Address for interfaces in proxy
    meta_arenas.setInterfaces(
        old_arenas.address, passes.address, esport.address, {"from": owner}
    )
    # Approve for Burn
    approve_burn_tx = old_arenas.approve(meta_arenas.address, 0, {"from": owner})
    # Migrate Arena
    migrate_tx = meta_arenas.migrateArena(0, {"from": owner})
