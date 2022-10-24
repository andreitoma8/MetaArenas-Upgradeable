// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@upopenzeppelin/contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import "@upopenzeppelin/contracts-upgradeable/contracts/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@upopenzeppelin/contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@upopenzeppelin/contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@upopenzeppelin/contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IArenas.sol";

/// @title Metarena Upgradable Smart Contract with non-custodial staking.
/// @author Andrei Toma
/// @notice Made using Upgradable Contracts from OpenZeppelin.
contract MetarenasV2 is
    Initializable,
    ERC721Upgradeable,
    OwnableUpgradeable,
    ERC721EnumerableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using StringsUpgradeable for uint256;

    // Interfaces
    // Interface for old Arenas Collection
    IArenas public oldArenas;
    // Interface for MetaPass Collection
    IERC1155 public passes;
    // Interface for ARENA Token
    IERC20 public arenaToken;
    // Interface for BYTE token
    IERC20 public byteToken;

    // Address with role of boost for Level
    address public levelBooster;

    // Admin address
    address private admin;

    // Minting state
    bool public paused;

    // Rewards in Byte state
    bool public byteEndabled;

    // Current supply
    uint256 private supply;

    // Mint price for Carbon Pass Holders
    uint256 public priceForCarbon;
    // Mint price for Gold Pass Holders
    uint256 public priceForGold;
    // Mint price for open sale
    uint256 public priceForAll;

    // Time of minting start for Gold(Unix Time)
    uint256 public mintStart;
    // Time of minting start for Carbon(Unix Time)
    uint256 public mintCarbonEnd;
    // Time of minting start for everyone(Unix Time)
    uint256 public mintGoldEnd;
    // Time of minting end for everyone(Unix Time)
    uint256 public mintEnd;

    // ARENA price for first Tier upgrade
    uint256 public arenaPriceForUpgrade;

    // BYTE price for first Tier upgrade
    uint256 public bytePriceForUpgrade;

    // The maximum amount that can be minted per tx
    uint256 public maxAmountPerTx;

    // The maximum supply. Can be enlarged by 1000
    // when new districts are added, but can't go
    // over 4000.
    uint256 private maxSupply;

    // URI for metadata
    string internal uri;

    // The file tipe for metadata
    string internal uriSuffix;

    // The time a Arena has to be staked for its Tier to be upgraded
    uint256 private timeToLevelUp;

    // Mapping of wallet address to staked Token IDs
    mapping(address => uint256[]) userArenasStaked;

    // Mapping of levels needed to upgrade for each tier
    mapping(uint256 => uint256) public levelsToUpgrade;

    // Mapping of rewards multiplier for Arena Tier
    // Tier rewards multipliers have 2 decimal
    mapping(uint256 => uint256) public tierRewardsMultiplier;

    // Mapping of rewards per day to Arena Rarity
    mapping(uint256 => uint256) public rarityRewardsPerDay;

    // Arena info
    struct Arena {
        // Staked state
        bool staked;
        // Tier of the arena
        uint256 tier;
        // Level of the arena
        uint256 level;
        // Rarity of the Arena(0: Common, 1: Uncommon, 2: Rare, 3: Epic, 4: Legendary)
        uint256 rarity;
        // The time Arena was staked at
        uint256 timeOfStake;
        // Last time of update for this Arena
        uint256 timeOfLastRewardUpdate;
        // Calculated, but unclaimed rewards for the Arena
        uint256 unclaimedRewardsArena;
        uint256 unclaimedRewardsByte;
    }

    // Mapping of Arena Token ID to Arena info struct
    mapping(uint256 => Arena) public arenas;

    event TierUpgraded(uint256 indexed _tier, uint256 indexed _arenaId);

    /// @notice modifier used for functions where only the Owner or the Admin have access
    modifier onlyOwnerOrAdmin() {
        require(msg.sender == owner() || msg.sender == admin);
        _;
    }

    /// @notice assures the mint per transaction amount and the max supply are respected
    /// @param _amount the amount to mint
    modifier mintCompliance(uint256 _amount) {
        require(
            _amount <= maxAmountPerTx,
            "Maximum mint per transaction exceeded!"
        );
        require(supply + _amount <= maxSupply, "Max supply exceeded!");
        require(!paused, "Minting is paused!");
        _;
    }

    /// @notice function for Arena NFT migration from the old collection
    /// @param _tokenId the token ID for the arena to be burned from the old Arena Contract
    /// @dev approve() function should be already called with the address of this Contract and the same token ID
    function migrateArena(uint256 _tokenId) external {
        oldArenas.burn(_tokenId);
        _safeMint(msg.sender, _tokenId + 1);
    }

    /// @notice mint function with 3 stages with access and prices based on Metapasses ownership
    /// @param _amount the amount of Metarenas to mint
    /// @dev need to approve ARENA token transfer before calling this function
    function mint(uint256 _amount) external payable mintCompliance(_amount) {
        if (block.timestamp >= mintStart && block.timestamp <= mintCarbonEnd) {
            require(
                passes.balanceOf(msg.sender, 0) > 0,
                "You don't own Carbon MetaPass"
            );
            arenaToken.transferFrom(
                msg.sender,
                address(this),
                priceForCarbon * _amount
            );
        } else if (block.timestamp <= mintGoldEnd) {
            require(
                passes.balanceOf(msg.sender, 1) > 0 ||
                    passes.balanceOf(msg.sender, 0) > 0,
                "You don't own Carbon or Gold MetaPass"
            );
            arenaToken.transferFrom(
                msg.sender,
                address(this),
                priceForGold * _amount
            );
        } else if (block.timestamp <= mintEnd) {
            arenaToken.transferFrom(
                msg.sender,
                address(this),
                priceForAll * _amount
            );
        } else {
            revert("Minting not live");
        }
        _mintLoop(msg.sender, _amount);
    }

    /// @notice free mint function for Owner of the Smart Contract, used for giveaways and partnerships
    /// @param _mintAmount the amount of tokens to mint
    /// @param _receiver the address to mint to
    function mintForAddress(uint256 _mintAmount, address _receiver)
        public
        mintCompliance(_mintAmount)
        onlyOwner
    {
        _mintLoop(_receiver, _mintAmount);
    }

    /// @notice function called to stake Metarenas
    /// @param _arenaTokenId the token Id of the Metarena to be staked
    function stakeArena(uint256 _arenaTokenId) external nonReentrant {
        require(
            msg.sender == ownerOf(_arenaTokenId),
            "Can't stake a arena you don't own!"
        );
        Arena memory _arena = arenas[_arenaTokenId];
        require(!_arena.staked, "Arena already staked!");
        _arena.timeOfStake = block.timestamp;
        _arena.staked = true;
        _arena.timeOfLastRewardUpdate = block.timestamp;
        arenas[_arenaTokenId] = _arena;
        userArenasStaked[msg.sender].push(_arenaTokenId);
    }

    /// @notice function called to unstake Metarenas
    /// @param _arenaTokenId the token Id of the Metarena to be unstaked
    function unstakeArena(uint256 _arenaTokenId) external nonReentrant {
        require(
            msg.sender == ownerOf(_arenaTokenId),
            "You are not the owner of this Arena!"
        );
        Arena memory _arena = arenas[_arenaTokenId];
        require(_arena.staked, "Arena is not staked!");
        uint256 arenaRewards = calculateRewardsArena(_arenaTokenId);
        _arena.unclaimedRewardsArena += arenaRewards;
        uint256 byteRewards = calculateRewardsByte(_arenaTokenId);
        _arena.unclaimedRewardsByte += byteRewards;
        _arena.staked = false;
        _arena.level = calculateArenaLevel(_arenaTokenId);
        _arena.timeOfStake = 0;
        _arena.timeOfLastRewardUpdate = block.timestamp;
        arenas[_arenaTokenId] = _arena;
        uint256[] memory _userArenasStaked = userArenasStaked[msg.sender];
        for (uint256 i; i < _userArenasStaked.length; ++i) {
            if (_userArenasStaked[i] == _arenaTokenId) {
                _userArenasStaked[i] = _userArenasStaked[
                    _userArenasStaked.length - 1
                ];
            }
        }
        userArenasStaked[msg.sender] = _userArenasStaked;
        userArenasStaked[msg.sender].pop();
    }

    /// @notice function used to claim the rewards accumulated for a Metarena
    /// @param _arenaTokenId the token ID of the Metarena selected to claim rewards from
    /// @dev Only sends $ARENA rewards if $BYTE is not enabled
    function claimRewards(uint256 _arenaTokenId) external nonReentrant {
        require(
            msg.sender == ownerOf(_arenaTokenId),
            "You don't own this arena!"
        );
        uint256 arenaRewards = calculateRewardsArena(_arenaTokenId) +
            arenas[_arenaTokenId].unclaimedRewardsArena;
        require(arenaRewards > 0, "You have no rewards to claim");
        if (byteEndabled) {
            uint256 byteRewards = calculateRewardsByte(_arenaTokenId) +
                arenas[_arenaTokenId].unclaimedRewardsByte;
            require(byteRewards > 0, "You have no rewards to claim");
            arenas[_arenaTokenId].unclaimedRewardsByte = 0;
            byteToken.transfer(msg.sender, byteRewards);
        }
        arenas[_arenaTokenId].timeOfLastRewardUpdate = block.timestamp;
        arenas[_arenaTokenId].unclaimedRewardsArena = 0;
        arenaToken.transfer(msg.sender, arenaRewards);
    }

    /// @notice function called by the Level Booster address to increase the level of an Metarena
    /// @param _arenaTokenId the token ID of the Metarena to be boosted
    /// @param _levelsToIncrease the amount of levels to add to the Metarena
    function increaseLevel(uint256 _arenaTokenId, uint256 _levelsToIncrease)
        external
    {
        require(
            msg.sender == levelBooster,
            "You are not authorised to call this function!"
        );
        arenas[_arenaTokenId].level += _levelsToIncrease;
    }

    /// @notice upgrades the tier of the Metarena when user has required levels
    /// @param _arenaTokenId the token ID of the Metarena to be upgraded
    function upgradeArenaTier(uint256 _arenaTokenId) external nonReentrant {
        require(
            ownerOf(_arenaTokenId) == msg.sender,
            "Can't upgrade tier for tokens you don't own!"
        );
        Arena memory _arena = arenas[_arenaTokenId];
        uint256 _level = calculateArenaLevel(_arenaTokenId);
        require(
            _level >= levelsToUpgrade[_arena.tier],
            "Not high enough level to upgrade"
        );
        arenaToken.transferFrom(
            msg.sender,
            address(this),
            arenaPriceForUpgrade * _arena.tier
        );
        _arena.unclaimedRewardsArena += calculateRewardsArena(_arenaTokenId);
        if (byteEndabled) {
            byteToken.transferFrom(
                msg.sender,
                address(this),
                bytePriceForUpgrade * _arena.tier
            );
            _arena.unclaimedRewardsByte += calculateRewardsByte(_arenaTokenId);
        }
        _arena.timeOfLastRewardUpdate = block.timestamp;
        _arena.tier += 1;
        arenas[_arenaTokenId] = _arena;

        emit TierUpgraded(_arena.tier, _arenaTokenId);
    }

    /// @notice sets the addresses of the other Contracts in the ecosystem
    /// @param _oldArenas the address for the old Arenas Contract
    /// @param _passes the address for the Metapasses Contract
    /// @param _arenaToken the address for the $ARENA Token Contract
    function setInterfaces(
        IArenas _oldArenas,
        IERC1155 _passes,
        IERC20 _arenaToken
    ) external onlyOwnerOrAdmin {
        oldArenas = _oldArenas;
        passes = _passes;
        arenaToken = _arenaToken;
    }

    /// @notice change the state of minting
    /// @param _paused true = minting is paused, false = minting is resumed
    function setPaused(bool _paused) external onlyOwnerOrAdmin {
        paused = _paused;
    }

    /// @notice set the address for the $BYTE Token Contract
    /// @param _address he $BYTE Token Contract address
    function setByteToken(IERC20 _address) external onlyOwnerOrAdmin {
        byteToken = _address;
    }

    /// @notice enable the $BYTE token in the Contract
    /// @param _bool the state of $BYTE usability
    function setByteEnabled(bool _bool) external onlyOwnerOrAdmin {
        byteEndabled = _bool;
    }

    /// @notice sets the prices for Tier upgrade
    /// @param _priceForUpgradeArena the price to pay in $ARENA Token
    /// @param _priceForUpgradeByte the price to pay in $BYTE Token
    function setPriceForUpgrade(
        uint256 _priceForUpgradeArena,
        uint256 _priceForUpgradeByte
    ) external onlyOwnerOrAdmin {
        arenaPriceForUpgrade = _priceForUpgradeArena;
        bytePriceForUpgrade = _priceForUpgradeByte;
    }

    /// @notice set the mint cost of one Metarena
    /// @param _carbon the mint price for Carbon Metapass holders
    /// @param _gold the mint price for Gold Metapass holders
    /// @param _all the mint price for public sale
    function setPrice(
        uint256 _carbon,
        uint256 _gold,
        uint256 _all
    ) public onlyOwnerOrAdmin {
        priceForCarbon = _carbon;
        priceForGold = _gold;
        priceForAll = _all;
    }

    /// @notice set the maximum mint amount per transaction
    /// @param _maxMintAmountPerTx the maximum amount allowed
    function setMaxMintAmountPerTx(uint256 _maxMintAmountPerTx)
        public
        onlyOwnerOrAdmin
    {
        maxAmountPerTx = _maxMintAmountPerTx;
    }

    /// @notice set the URI of IPFS/hosting server for the metadata folder
    /// @param _uri the URI used in the format: "ipfs://your_uri/"
    function setUri(string memory _uri) public onlyOwnerOrAdmin {
        uri = _uri;
    }

    /// @notice set the address that is allowed to increase levels of a Metarena
    /// @param _levelBooster the address of the level booster
    function setLevelBooster(address _levelBooster) external onlyOwnerOrAdmin {
        levelBooster = _levelBooster;
    }

    /// @notice set a address for the admin function
    /// @param _admin the admin's address
    function setAdmin(address _admin) external onlyOwner {
        admin = _admin;
    }

    /// @notice set the minting period for future mints of new Districts
    /// @param _mintStart the start of the minting phase only for Carbon Metapass holders
    /// @param _mintCarbonEnd the start of the minting phase for both Carbon and Gold Metapass holders
    /// @param _mintGoldEnd the start of the public minting phase
    /// @param _mintEnd the end of the minting period
    /// @dev all the times are expressed in UNIX fromat
    function setMintingPeriods(
        uint256 _mintStart,
        uint256 _mintCarbonEnd,
        uint256 _mintGoldEnd,
        uint256 _mintEnd
    ) external onlyOwnerOrAdmin {
        mintStart = _mintStart;
        mintCarbonEnd = _mintCarbonEnd;
        mintGoldEnd = _mintGoldEnd;
        mintEnd = _mintEnd;
    }

    /// @notice adds a new district by increading the maximum supply of the collection by 1000
    function addDistrict() external onlyOwnerOrAdmin {
        require(maxSupply <= 4000);
        maxSupply += 1000;
    }

    /// @notice add onchain metadata for Arena Rarity
    /// @param _tokenIds array of all the token IDs
    /// @param _rarity array of coresponding rarity for the token IDs(0: Common, 1: Uncommon, 2: Rare, 3: Epic, 4: Legendary)
    function setRarity(uint256[] memory _tokenIds, uint256[] memory _rarity)
        external
        onlyOwnerOrAdmin
    {
        require(_tokenIds.length == _rarity.length);
        for (uint256 i; i < _tokenIds.length; ++i) {
            require(_rarity[i] < 5);
            arenas[_tokenIds[i]].rarity = _rarity[i];
        }
    }

    /// @notice set the reawards per day based on Arena rarity
    /// @param _rarity rarity(0: Common, 1: Uncommon, 2: Rare, 3: Epic, 4: Legendary)
    /// @param _rewards the amount of rewards to distribute in one day
    function setRarityRewards(uint256 _rarity, uint256 _rewards)
        external
        onlyOwnerOrAdmin
    {
        rarityRewardsPerDay[_rarity] = _rewards;
    }

    /// @notice set the rewards multiplier for Arena tier
    /// @param _tier the tier to set the multiplier for
    /// @param _multiplier the multiplier to set
    /// @dev set with one decimal(exaplme: 10 == 1.0)
    function setTierMultiplier(uint256 _tier, uint256 _multiplier)
        external
        onlyOwnerOrAdmin
    {
        tierRewardsMultiplier[_tier] = _multiplier;
    }

    /// @notice withdraw function for owner
    /// @param _amountArena amount of $ARENA token to withdraw
    /// @param _amountByte amount of $BYTE token to withdraw if BYTE is enabled
    function withdraw(uint256 _amountArena, uint256 _amountByte)
        public
        onlyOwner
    {
        uint256 _balanceArena = arenaToken.balanceOf(address(this));
        require(_amountArena <= _balanceArena);
        arenaToken.transfer(msg.sender, _amountArena);
        if (byteEndabled) {
            uint256 _balanceByte = byteToken.balanceOf(address(this));
            require(_amountByte <= _balanceByte);
            byteToken.transfer(msg.sender, _amountByte);
        }
    }

    /// @notice returns token Ids of Staked Metarenas
    /// @param _user the address to query for
    function userStakedArenas(address _user)
        public
        view
        returns (uint256[] memory)
    {
        return userArenasStaked[_user];
    }

    /// @notice returns rewards available to claim for Metarena
    /// @param _arenaTokenId the token ID to query for
    function availableRewards(uint256 _arenaTokenId)
        public
        view
        returns (uint256, uint256)
    {
        uint256 _rewardsArena = arenas[_arenaTokenId].unclaimedRewardsArena +
            calculateRewardsArena(_arenaTokenId);
        uint256 _rewardsByte;
        if (byteEndabled) {
            _rewardsByte =
                arenas[_arenaTokenId].unclaimedRewardsByte +
                calculateRewardsByte(_arenaTokenId);
        } else {
            _rewardsByte = 0;
        }
        return (_rewardsArena, _rewardsByte);
    }

    /// @notice returns arena detalis for Metarena
    /// @param _arenaTokenId the token ID to query for
    function arenaDetails(uint256 _arenaTokenId)
        public
        view
        returns (
            uint256 arenaTier_,
            uint256 arenaLevel_,
            uint256 arenaRarity_,
            bool staked_,
            bool canUpgrade_,
            uint256 timeOfStake_
        )
    {
        uint256 _arenaLevel = calculateArenaLevel(_arenaTokenId);
        bool _canUpgrade = _arenaLevel >=
            levelsToUpgrade[arenas[_arenaTokenId].tier];
        return (
            arenas[_arenaTokenId].tier,
            _arenaLevel,
            arenas[_arenaTokenId].rarity,
            arenas[_arenaTokenId].staked,
            _canUpgrade,
            arenas[_arenaTokenId].timeOfStake
        );
    }

    /// @notice returns the Token Id for Tokens owned by the specified address
    /// @param _owner the address to query for
    function tokensOfOwner(address _owner)
        public
        view
        returns (uint256[] memory)
    {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory ownedTokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; ++i) {
            ownedTokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return ownedTokenIds;
    }

    /// @notice returns the Token URI with Metadata
    /// @param _tokenId the token ID to return Metadata for
    function tokenURI(uint256 _tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _exists(_tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );
        string memory currentBaseURI = _baseURI();
        return
            bytes(currentBaseURI).length > 0
                ? string(
                    abi.encodePacked(
                        currentBaseURI,
                        _tokenId.toString(),
                        uriSuffix
                    )
                )
                : "";
    }

    /// @notice helper function that returns the base URI
    function _baseURI() internal view virtual override returns (string memory) {
        return uri;
    }

    /// @notice loop for minting multiple NFTs in one transaction
    /// @param _receiver the address to mint to
    /// @param _mintAmount the amount of tokens to mint
    function _mintLoop(address _receiver, uint256 _mintAmount) internal {
        for (uint256 i = 0; i < _mintAmount; i++) {
            supply++;
            _safeMint(_receiver, supply);
        }
    }

    /// @notice calculate the $BYTE rewards accumulated by the Metarena since the last update
    /// @param _arenaTokenId the token ID of the Metarena
    function calculateRewardsByte(uint256 _arenaTokenId)
        internal
        view
        returns (uint256 _rewards)
    {
        if (arenas[_arenaTokenId].staked) {
            return ((((block.timestamp -
                arenas[_arenaTokenId].timeOfLastRewardUpdate) *
                tierRewardsMultiplier[arenas[_arenaTokenId].tier]) *
                (rarityRewardsPerDay[arenas[_arenaTokenId].rarity])) / 864000);
        } else {
            return 0;
        }
    }

    /// @notice calculate the $ARENArewards accumulated by the Metarena since the last update
    /// @param _arenaTokenId the token ID of the Metarena
    function calculateRewardsArena(uint256 _arenaTokenId)
        internal
        view
        returns (uint256 _rewards)
    {
        if (arenas[_arenaTokenId].staked) {
            return ((((block.timestamp -
                arenas[_arenaTokenId].timeOfLastRewardUpdate) *
                tierRewardsMultiplier[arenas[_arenaTokenId].tier]) *
                (rarityRewardsPerDay[arenas[_arenaTokenId].rarity])) / 864000);
        } else {
            return 0;
        }
    }

    /// @notice returns arena level
    /// @param _arenaTokenId the token ID of the Metarena
    function calculateArenaLevel(uint256 _arenaTokenId)
        internal
        view
        returns (uint256)
    {
        if (arenas[_arenaTokenId].timeOfStake == 0) {
            return (arenas[_arenaTokenId].level);
        } else {
            return
                ((block.timestamp - arenas[_arenaTokenId].timeOfStake) /
                    timeToLevelUp) + arenas[_arenaTokenId].level;
        }
    }

    /// @notice override function to block token transfers when tokenId is staked and reset Metarena level on transfer
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        require(!arenas[tokenId].staked, "You can't transfer staked arenas!");
        arenas[tokenId].level = 0;
        super._beforeTokenTransfer(from, to, tokenId);
    }

    /// @notice override required by Solidity
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
