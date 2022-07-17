from brownie import (
    Contract,
    Metarenas,
    ProxyAdmin,
    TransparentUpgradeableProxy,
    accounts,
    config,
)
from scripts.helpful_scripts import encode_function_data, getArenaRarities

verification = True
old_arenas_address = "0x5726b8D291b69Cf7252785917cDD813e119eBb82"
arena_token_address = "0x0110F74379F0428Bb2362823e134544DE5e79693"
metapasses_address = "0x4867f7ACb9078d2b462442c5ca3DBa01456844B5"
matts_address = "0x6ff7095144c856422c09102Bf0606506Dae6f370"


def main():
    owner = accounts.add(config["wallets"]["from_key"])
    # Deploy Proxy Admin
    proxy_admin = ProxyAdmin.deploy({"from": owner}, publish_source=verification)
    # Deploy implementation SC
    implementation = Metarenas.deploy({"from": owner}, publish_source=verification)
    # Encode initializer function
    encoded_initializer_function = encode_function_data(implementation.initialize)
    # Deploy and initialize proxy contract
    proxy = TransparentUpgradeableProxy.deploy(
        implementation.address,
        proxy_admin.address,
        encoded_initializer_function,
        {"from": owner},
        publish_source=verification,
    )
    # Set up Metarena SC
    meta_arenas = Contract.from_abi("Metarenas", proxy.address, Metarenas.abi)
    # Set interfaces for other contracts
    meta_arenas.setInterfaces(
        old_arenas_address, metapasses_address, arena_token_address, {"from": owner}
    )
    # Set admin
    meta_arenas.setAdmin(owner.address, {"from": owner})
    # Transfer ownership
    meta_arenas.transferOwnership(matts_address, {"from": owner})
    # Set on-chain rarities
    values = getArenaRarities()
    meta_arenas.setRarity(values[0], values[1], {"from": owner})
    print(f"Meta Arenas address: {meta_arenas.address}")
