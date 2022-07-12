// SPDX-License-Identifier: MIT
// Creator: andreitoma8
pragma solidity ^0.8.4;

import "@upopenzeppelin/contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import "@upopenzeppelin/contracts-upgradeable/contracts/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@upopenzeppelin/contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@upopenzeppelin/contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@upopenzeppelin/contracts-upgradeable/contracts/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/IArenas.sol";

contract MetaArenasV2 is
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
    // Interface for ESPORT Token
    IERC20 public esportToken;
    // Interface for BYTE token
    IERC20 public byteToken;

    // Address with role of boost for Level
    address public levelBooster;

    // Admin
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

    // ESPORT price for first Tier upgrade
    uint256 public esportPriceForUpgrade;

    // BYTE price for first Tier upgrade
    uint256 public bytePriceForUpgrade;

    // The maximum amount that can be minted per tx
    uint256 public maxAmountPerTx;

    // The maximum supply. Can be enlarged by 1000
    // when new districts are added, but can't go
    // over 4000.
    uint256 private maxSupply;

    // Uri for metadata
    string internal uri;

    // The file time for metadata
    string internal uriSuffix;

    // Levels needed to upgrade form tier to tier
    uint256 public levelsForUpgrade;

    // The time a Arena has to be staked for it's Tier to be upgraded
    uint256 private timeToLevelUp;

    // Rewards of $ESPORT per hour per token deposited in wei
    uint256 public rewardsPerHourEsport;

    // Rewards of $BYTE per hour per token deposited in wei
    uint256 public rewardsPerHourByte;

    // Rewards multiplier per tier
    uint256 public tierMultiplier;

    // User arenas staked
    mapping(address => uint256[]) userArenasStaked;

    // Mapping of Token Id to staker. Made for the SC to remeber
    // who to send back the ERC721 Token to.
    mapping(uint256 => address) public stakerAddress;

    // Arena info
    struct Arena {
        // Staked state
        bool staked;
        // Tier of the arena
        uint256 tier;
        // XP Level of the arena
        uint256 level;
        // Rarity of the Arena(0: Common, 1: Uncommon, 2: Rare, 3: Epic, 4: Legendary)
        uint256 rarity;
        // The time arena was staked at
        uint256 timeOfStake;
        // Last time of details update for this Arena
        uint256 timeOfLastRewardUpdate;
        // Calculated, but unclaimed rewards for the User. The rewards are
        // calculated each time the user writes to the Smart Contract
        uint256 unclaimedRewardsEsport;
        uint256 unclaimedRewardsByte;
    }

    // Mapping of Arena Token ID to Arena info
    mapping(uint256 => Arena) public arenas;

    constructor() initializer {}

    function initialize() public initializer {
        __ERC721_init("MetaArenas", "MARE");
        __Ownable_init();
        __ReentrancyGuard_init();
        priceForCarbon = 10 * 10**18;
        priceForGold = 15 * 10**18;
        priceForAll = 20 * 10**18;
        esportPriceForUpgrade = 100 * 10**18;
        bytePriceForUpgrade = 200 * 10**18;
        maxAmountPerTx = 3;
        maxSupply = 1000;
        uriSuffix = ".json";
        levelsForUpgrade = 10;
        timeToLevelUp = 259200; //172800;
        rewardsPerHourEsport = 100000;
        rewardsPerHourByte = 50000;
        tierMultiplier = 2;
        supply = 1000;
        paused = true;
        // Mint Arenas 118, 188 and 216 to owner.(A mistake was made in the previous SC
        // and we'll redistribute these Arenas back to the owners)
        _safeMint(msg.sender, 118);
        _safeMint(msg.sender, 188);
        _safeMint(msg.sender, 216);
    }

    modifier onlyOwnerOrAdmin() {
        require(msg.sender == owner() || msg.sender == admin);
        _;
    }

    /////////////
    // Minting //
    /////////////

    // Assures the mint per transaction amount and
    // the max supply are respected
    modifier mintCompliance(uint256 _amount) {
        require(
            _amount <= maxAmountPerTx,
            "Maximum mint per transaction exceeded!"
        );
        require(supply + _amount <= maxSupply, "Max supply exceeded!");
        require(!paused, "Minting is paused!");
        _;
    }

    // Function for Arena NFT migration from the old collection
    function migrateArena(uint256 _tokenId) external {
        oldArenas.burn(_tokenId);
        _safeMint(msg.sender, _tokenId + 1);
    }

    // Mint function
    // Need to approve ESPORT token transfer before calling
    function mint(uint256 _amount) external payable mintCompliance(_amount) {
        if (block.timestamp >= mintStart && block.timestamp <= mintCarbonEnd) {
            require(
                passes.balanceOf(msg.sender, 0) > 0,
                "You don't own Carbon MetaPass"
            );
            esportToken.transferFrom(
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
            esportToken.transferFrom(
                msg.sender,
                address(this),
                priceForGold * _amount
            );
        } else if (block.timestamp <= mintEnd) {
            esportToken.transferFrom(
                msg.sender,
                address(this),
                priceForAll * _amount
            );
        } else {
            revert("Minting not live");
        }
        _mintLoop(msg.sender, _amount);
    }

    // Free mint function for Owner of the Smart Contract, used for Giveaways
    function mintForAddress(uint256 _mintAmount, address _receiver)
        public
        mintCompliance(_mintAmount)
        onlyOwner
    {
        _mintLoop(_receiver, _mintAmount);
    }

    /////////////
    // Staking //
    /////////////

    // Function to stake arena
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

    // Function to unstake arena
    function unstakeArena(uint256 _arenaTokenId) external nonReentrant {
        require(
            msg.sender == ownerOf(_arenaTokenId),
            "You are not the owner of this Arena!"
        );
        Arena memory _arena = arenas[_arenaTokenId];
        require(_arena.staked, "Arena is not staked!");
        uint256 esportRewards = calculateRewardsEsport(_arenaTokenId);
        _arena.unclaimedRewardsEsport += esportRewards;
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

    // Calculate rewards for the msg.sender, check if there are any rewards
    // claim, set unclaimedRewards to 0 and transfer the ERC20 Reward token
    // to the user.
    function claimRewards(uint256 _arenaTokenId) external nonReentrant {
        require(
            msg.sender == ownerOf(_arenaTokenId),
            "You don't own this arena!"
        );
        uint256 esportRewards = calculateRewardsEsport(_arenaTokenId) +
            arenas[_arenaTokenId].unclaimedRewardsEsport;
        require(esportRewards > 0, "You have no rewards to claim");
        if (byteEndabled) {
            uint256 byteRewards = calculateRewardsByte(_arenaTokenId) +
                arenas[_arenaTokenId].unclaimedRewardsByte;
            require(byteRewards > 0, "You have no rewards to claim");
            arenas[_arenaTokenId].unclaimedRewardsByte = 0;
            byteToken.transfer(msg.sender, byteRewards);
        }
        arenas[_arenaTokenId].timeOfLastRewardUpdate = block.timestamp;
        arenas[_arenaTokenId].unclaimedRewardsEsport = 0;
        esportToken.transfer(msg.sender, esportRewards);
    }

    ////////////////////
    // Level and Tier //
    ////////////////////

    // Function called by level booster to increse arena level
    function increaseLevel(uint256 _arenaTokenId, uint256 _levelsToIncrease)
        external
    {
        require(
            msg.sender == levelBooster,
            "You are not authorised to call this function!"
        );
        arenas[_arenaTokenId].level += _levelsToIncrease;
    }

    // Upgrade the tier of your arena when you have the necesary level
    function upgradeArenaTier(uint256 _arenaTokenId) external nonReentrant {
        require(
            ownerOf(_arenaTokenId) == msg.sender,
            "Can't upgrade tier for tokens you don't own!"
        );
        Arena memory _arena = arenas[_arenaTokenId];
        uint256 _level = calculateArenaLevel(_arenaTokenId);
        require(
            _level >= (_arena.tier + 1) * levelsForUpgrade,
            "Not high enough level to upgrade"
        );
        esportToken.transferFrom(
            msg.sender,
            address(this),
            esportPriceForUpgrade * _arena.tier
        );
        _arena.unclaimedRewardsEsport += calculateRewardsEsport(_arenaTokenId);
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
    }

    ///////////
    // Admin //
    ///////////

    // Set the address for other SC in the ecosystem
    function setInterfaces(
        IArenas _oldArenas,
        IERC1155 _passes,
        IERC20 _esportToken
    ) external onlyOwnerOrAdmin {
        oldArenas = _oldArenas;
        passes = _passes;
        esportToken = _esportToken;
    }

    // Set paused state for minting
    function setPaused(bool _paused) external onlyOwnerOrAdmin {
        paused = _paused;
    }

    // Set the Byte Token Smart Contract
    function setByteToken(IERC20 _address) external onlyOwnerOrAdmin {
        byteToken = _address;
    }

    // Set if byte enabled in the system
    function setByteEnabled(bool _bool) external onlyOwnerOrAdmin {
        byteEndabled = _bool;
    }

    // Set the prices for Arena Upgrade
    function setPriceForUpgrade(
        uint256 _priceForUpgradeEsport,
        uint256 _priceForUpgradeByte
    ) external onlyOwnerOrAdmin {
        esportPriceForUpgrade = _priceForUpgradeEsport;
        bytePriceForUpgrade = _priceForUpgradeByte;
    }

    // Set rewards (everyone needs to claim rewards or unstake their arena
    // before the rewards per hour is set or they might lose some of their
    // accumulated rewards)
    function setRewardsPerHour(
        uint256 _rewardsPerHourEsport,
        uint256 _rewardsPerHourByte
    ) external onlyOwner {
        rewardsPerHourEsport = _rewardsPerHourEsport;
        rewardsPerHourByte = _rewardsPerHourByte;
    }

    // Set the mint cost of one NFT
    function setPrice(
        uint256 _carbon,
        uint256 _gold,
        uint256 _all
    ) public onlyOwnerOrAdmin {
        priceForCarbon = _carbon;
        priceForGold = _gold;
        priceForAll = _all;
    }

    // Set the maximum mint amount per transaction
    function setMaxMintAmountPerTx(uint256 _maxMintAmountPerTx)
        public
        onlyOwnerOrAdmin
    {
        maxAmountPerTx = _maxMintAmountPerTx;
    }

    // The URI of IPFS/hosting server for the metadata folder.
    // Used in the format: "ipfs://your_uri/".
    function setUri(string memory _uri) public onlyOwnerOrAdmin {
        uri = _uri;
    }

    function setLevelBooster(address _levelBooster) external onlyOwnerOrAdmin {
        levelBooster = _levelBooster;
    }

    // Set a address for the admin function
    function setAdmin(address _admin) external onlyOwner {
        admin = _admin;
    }

    // Set the minting period for next districts
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

    function addDistrict() external onlyOwnerOrAdmin {
        require(maxSupply <= 4000);
        maxSupply += 1000;
    }

    // Add onchain metadata for Arena Rarity
    function addRarity(uint256[] memory _tokenIds, uint256[] memory _rarity)
        external
        onlyOwnerOrAdmin
    {
        require(_tokenIds.length == _rarity.length);
        for (uint256 i; i < _tokenIds.length; ++i) {
            require(_rarity[i] < 5);
            arenas[_tokenIds[i]].rarity = _rarity[i];
        }
    }

    // Withdraw ETH after sale
    function withdraw(uint256 _amountEsport, uint256 _amountByte)
        public
        onlyOwner
    {
        uint256 _balanceEsport = esportToken.balanceOf(address(this));
        require(_amountEsport <= _balanceEsport);
        esportToken.transfer(msg.sender, _amountEsport);
        if (byteEndabled) {
            uint256 _balanceByte = byteToken.balanceOf(address(this));
            require(_amountByte <= _balanceByte);
            byteToken.transfer(msg.sender, _amountByte);
        }
    }

    //////////
    // View //
    //////////

    //Returns Token Ids of Staked Arenas of arg _user
    function userStakedArenas(address _user)
        public
        view
        returns (uint256[] memory)
    {
        return userArenasStaked[_user];
    }

    // Returns rewards available to claim for Arena
    function availableRewards(uint256 _arenaTokenId)
        public
        view
        returns (uint256, uint256)
    {
        uint256 _rewardsEsport = arenas[_arenaTokenId].unclaimedRewardsEsport +
            calculateRewardsEsport(_arenaTokenId);
        uint256 _rewardsByte;
        if (byteEndabled) {
            _rewardsByte =
                arenas[_arenaTokenId].unclaimedRewardsByte +
                calculateRewardsByte(_arenaTokenId);
        } else {
            _rewardsByte = 0;
        }
        return (_rewardsEsport, _rewardsByte);
    }

    // Returns arena detalis for Arena Token ID passed as arg
    function arenaDetails(uint256 _arenaTokenId)
        public
        view
        returns (
            uint256 arenaTier_,
            uint256 arenaLevel_,
            uint256 timeToWaitForLevelUp_,
            bool staked_,
            bool canUpgrade_
        )
    {
        uint256 _arenaTier = arenas[_arenaTokenId].tier;
        bool _canUpgrade = arenas[_arenaTokenId].level >=
            (arenas[_arenaTokenId].tier + 1) * levelsForUpgrade;
        uint256 _arenaLevel = calculateArenaLevel(_arenaTokenId);
        uint256 _timeToWaitForLevelUp;
        if (arenas[_arenaTokenId].staked) {
            _timeToWaitForLevelUp =
                (timeToLevelUp * (_arenaLevel + 1)) -
                (block.timestamp - arenas[_arenaTokenId].timeOfStake);
        } else {
            _timeToWaitForLevelUp = timeToLevelUp;
        }
        return (
            _arenaTier,
            _arenaLevel,
            _timeToWaitForLevelUp,
            arenas[_arenaTokenId].staked,
            _canUpgrade
        );
    }

    // Returns the Token Id for Tokens owned by the specified address
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

    // Returns the Token URI with Metadata for specified Token Id
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

    /////////////
    // Internal//
    /////////////

    // Helper function
    function _baseURI() internal view virtual override returns (string memory) {
        return uri;
    }

    // Loop for minting multiple NFTs in one transaction
    function _mintLoop(address _receiver, uint256 _mintAmount) internal {
        for (uint256 i = 0; i < _mintAmount; i++) {
            supply++;
            _safeMint(_receiver, supply);
        }
    }

    // Calculate rewards for param _staker by calculating the time passed
    // since last update in hours and mulitplying it to ERC721 Tokens Staked
    // and rewardsPerHour.
    function calculateRewardsEsport(uint256 _arenaTokenId)
        internal
        view
        returns (uint256 _rewards)
    {
        if (arenas[_arenaTokenId].staked) {
            return ((((block.timestamp -
                arenas[_arenaTokenId].timeOfLastRewardUpdate) *
                rewardsPerHourEsport) *
                (arenas[_arenaTokenId].tier + tierMultiplier)) / 3600);
        } else {
            return 0;
        }
    }

    function calculateRewardsByte(uint256 _arenaTokenId)
        internal
        view
        returns (uint256 _rewards)
    {
        if (arenas[_arenaTokenId].staked) {
            return ((((block.timestamp -
                arenas[_arenaTokenId].timeOfLastRewardUpdate) *
                rewardsPerHourByte) *
                (arenas[_arenaTokenId].tier + tierMultiplier)) / 3600);
        } else {
            return 0;
        }
    }

    // Returns arena level for arg Arena Token ID
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

    // Just because you never know
    receive() external payable {}

    // The following functions are overrides required by Solidity.

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        require(!arenas[tokenId].staked, "You can't transfer staked arenas!");
        arenas[tokenId].level = 0;
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // Test function
    function test() external pure returns (string memory) {
        return ("test succesful!");
    }
}
