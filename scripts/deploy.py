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

verification = True


def main():
    # Deloy
    owner = accounts.add(config["wallets"]["from_key"])
    # Deploy Proxi Admin
    proxy_admin = ProxyAdmin.deploy({"from": owner}, publish_source=verification)
    esport = EsportToken.deploy({"from": owner}, publish_source=verification)
    passes = MetaPasses.deploy({"from": owner}, publish_source=verification)
    old_arenas = ArenasOld.deploy({"from": owner}, publish_source=verification)
    # Just for tests:
    for address in [
        "0x6ff7095144c856422c09102Bf0606506Dae6f370",
        "0x436d8Fa63c672797Fa7E30B0dc19dA42D50ebA51",
        "0x3D59f41684af9aB653bCFAc982c4595238E5D11e",
    ]:
        old_arenas.mintForAddress(20, address, {"from": owner})
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
