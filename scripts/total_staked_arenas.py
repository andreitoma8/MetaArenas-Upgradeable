from brownie import (
    Contract,
    Metarenas,
    accounts,
    config,
)

meta_arenas_address = "0x86640CC8C305f10BB88Daa970932d2d48de39811"


def main():
    meta_arenas = Contract.from_abi("Metarenas", meta_arenas_address, Metarenas.abi)
    total_supply = meta_arenas.totalSupply()
    total_staked_supply = 0
    for i in range(1, 1001):
        areana_details = meta_arenas.arenaDetails(i)
        if areana_details[3]:
            print(f"Metarena {i} is staked.")
            total_staked_supply += 1
        else:
            print(f"Metarena {i} is not staked.")
    print(f"Out of {total_supply} Metarenas, {total_staked_supply} are staked.")
