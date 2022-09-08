from brownie import (
    Contract,
    Metarenas,
    ArenaToken,
    accounts,
    config,
)

meta_arenas_address = "0x86640CC8C305f10BB88Daa970932d2d48de39811"
arena_token_address = "0x0110F74379F0428Bb2362823e134544DE5e79693"


def main():
    owner = accounts.add(config["wallets"]["from_key"])
    meta_arenas = Contract.from_abi(
        "Metarenas", meta_arenas_address, Metarenas.abi)
    arna = Contract.from_abi("ARNA Token", arena_token_address, ArenaToken.abi)
    arna.approve(meta_arenas_address, 100*10**18, {"from": owner})
    meta_arenas.upgradeArenaTier(287, {"from": owner})
    print(meta_arenas.arenaDetails(287))
