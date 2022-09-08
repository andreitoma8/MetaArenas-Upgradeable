from brownie import (
    MetarenasV2,
    accounts,
    config,
)
from scripts.helpful_scripts import upgrade


proxy = "0x86640CC8C305f10BB88Daa970932d2d48de39811"
proxy_admin = "0xA8a7243d55b6581DEC78c3113005Abe5abe20948"


def main():
    owner = accounts.add(config["wallets"]["from_key"])
    # Deploy Arenas V2
    implementation2 = MetarenasV2.deploy({"from": owner})
    # Upgrade
    upgrade(owner, proxy, implementation2, proxy_admin)
