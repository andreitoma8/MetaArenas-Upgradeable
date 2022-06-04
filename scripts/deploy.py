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
from scripts.helpful_scripts import encode_function_data, getArenaRarities
import csv

verification = True


def main():
    # Deloy
    owner = accounts.add(config["wallets"]["from_key"])
    # Deploy Proxi Admin
    proxy_admin = ProxyAdmin.deploy({"from": owner}, publish_source=verification)
    # byte = ByteToken.deploy({"from": owner}, publish_source=verification)
    esport = EsportToken.deploy({"from": owner}, publish_source=verification)
    passes = MetaPasses.deploy({"from": owner}, publish_source=verification)
    old_arenas = ArenasOld.deploy({"from": owner}, publish_source=verification)
    # old_arenas.mint(20, {"from": owner}, publish_source=verification)
    # Deploy the first MetaArenas implementation
    implementation = MetaArenas.deploy({"from": owner}, publish_source=False)
    # Encode the initializa function
    encoded_initializer_function = encode_function_data(implementation.initialize)
    print(encoded_initializer_function)
    proxy = TransparentUpgradeableProxy.deploy(
        implementation.address,
        proxy_admin.address,
        encoded_initializer_function,
        {"from": owner},
        publish_source=verification,
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
    # Set arena rarity
    values = getArenaRarities()
    meta_arenas.setRarity(values[0], values[1], {"from": owner})
    print(meta_arenas.arenaDetails(1))
