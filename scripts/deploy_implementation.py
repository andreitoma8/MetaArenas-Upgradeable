from brownie import (
    Metarenas,
    accounts,
    config,
)


def main():
    owner = accounts.add(config["wallets"]["from_key"])
    implementation = Metarenas.deploy({"from": owner}, publish_source=True)
