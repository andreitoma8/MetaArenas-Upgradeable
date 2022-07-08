from brownie import (
    Contract,
    Metarenas,
    ArenaToken,
    MetaPasses,
    ProxyAdmin,
    TransparentUpgradeableProxy,
    accounts,
    config,
)
from scripts.helpful_scripts import encode_function_data, getArenaRarities

verification = True
old_arenas_address = "0x5cC71f402CB60fcCaEfbCF06FC24b17dE57491c8"


def main():
    # Deloy
    owner = accounts.add(config["wallets"]["from_key"])
    # Deploy Proxi Admin
    proxy_admin = ProxyAdmin.deploy({"from": owner}, publish_source=verification)
    token = ArenaToken.deploy({"from": owner}, publish_source=verification)
    passes = MetaPasses.deploy({"from": owner}, publish_source=verification)
    implementation = Metarenas.deploy({"from": owner}, publish_source=False)
    encoded_initializer_function = encode_function_data(implementation.initialize)
    proxy = TransparentUpgradeableProxy.deploy(
        implementation.address,
        proxy_admin.address,
        encoded_initializer_function,
        {"from": owner},
        publish_source=verification,
    )
    meta_arenas = Contract.from_abi("MetaArenas", proxy.address, MetaArenas.abi)
    meta_arenas.setInterfaces(
        old_arenas_address, passes.address, token.address, {"from": owner}
    )
    values = getArenaRarities()
    meta_arenas.setRarity(values[0], values[1], {"from": owner})
    token.transfer(meta_arenas.address, 1000000 * 10 ** 18, {"from": owner})
    print(f"Old Arenas address: {old_arenas_address}")
    print(f"ARENA Token address: {token.address}")
    print(f"Meta Arenas address: {meta_arenas.address}")
