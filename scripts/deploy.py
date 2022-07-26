from brownie import (
    Contract,
    Metarenas,
    ArenasOld,
    ArenaTokenMock,
    MetaPasses,
    ProxyAdmin,
    TransparentUpgradeableProxy,
    accounts,
    config,
)
from scripts.helpful_scripts import encode_function_data, getArenaRarities

verification = True


def main():
    # Deloy
    owner = accounts.add(config["wallets"]["from_key"])
    # Deploy Proxi Admin
    proxy_admin = ProxyAdmin.deploy({"from": owner}, publish_source=verification)
    arena = ArenaTokenMock.deploy({"from": owner}, publish_source=verification)
    passes = MetaPasses.deploy({"from": owner}, publish_source=verification)
    old_arenas = ArenasOld.deploy({"from": owner}, publish_source=verification)
    for address in [
        "0x867deF42417c9Df8B947AAC0E3Abae840fF13E5f"
    ]:
        old_arenas.mintForAddress(10, address, {"from": owner})
    # Deploy the first MetaArenas implementation
    implementation = Metarenas.deploy({"from": owner}, publish_source=verification)
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
    meta_arenas = Contract.from_abi("Metarenas", proxy.address, Metarenas.abi)
    # Set the Address for interfaces in proxy
    meta_arenas.setInterfaces(
        old_arenas.address, passes.address, arena.address, {"from": owner}
    )
    arena.transfer(meta_arenas.address, 100000*10**18, {"from": owner})
    # # Approve for Burn
    # approve_burn_tx = old_arenas.approve(meta_arenas.address, 0, {"from": owner})
    # # Migrate Arena
    # migrate_tx = meta_arenas.migrateArena(0, {"from": owner})
    # Set arena rarity
    values = getArenaRarities()
    meta_arenas.setRarity(values[0], values[1], {"from": owner})
    # print(meta_arenas.arenaDetails(1))
