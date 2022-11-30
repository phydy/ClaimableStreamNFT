import { ethers } from 'hardhat'
import { BigNumber, Signer } from 'ethers'
import { assert } from 'chai'
import { KeeperRegistryCheckUpkeepGasUsageWrapper } from '../../../typechain/KeeperRegistryCheckUpkeepGasUsageWrapper'
import { getUsers, Personas } from '../../test-helpers/setup'
import {
  deployMockContract,
  MockContract,
} from '@ethereum-waffle/mock-contract'
import { abi as registryAbi } from '../../../artifacts/src/v0.8/KeeperRegistry.sol/KeeperRegistry.json'

let personas: Personas
let owner: Signer
let caller: Signer
let nelly: Signer
let registryMockContract: MockContract
let gasUsageWrapper: KeeperRegistryCheckUpkeepGasUsageWrapper

const upkeepId = 123

describe('KeeperRegistryCheckUpkeepGasUsageWrapper', () => {
  before(async () => {
    personas = (await getUsers()).personas
    owner = personas.Default
    caller = personas.Carol
    nelly = personas.Nelly

    registryMockContract = await deployMockContract(owner as any, registryAbi)
    const gasUsageWrapperFactory = await ethers.getContractFactory(
      'KeeperRegistryCheckUpkeepGasUsageWrapper',
    )
    gasUsageWrapper = await gasUsageWrapperFactory
      .connect(owner)
      .deploy(registryMockContract.address)
    await gasUsageWrapper.deployed()
  })

  describe('measureCheckGas()', () => {
    it("returns gas used when registry's checkUpkeep executes successfully", async () => {
      await registryMockContract.mock.checkUpkeep
        .withArgs(upkeepId, await nelly.getAddress())
        .returns(
          '0xabcd' /* performData */,
          BigNumber.from(1000) /* maxLinkPayment */,
          BigNumber.from(2000) /* gasLimit */,
          BigNumber.from(3000) /* adjustedGasWei */,
          BigNumber.from(4000) /* linkEth */,
        )

      const response = await gasUsageWrapper
        .connect(caller)
        .callStatic.measureCheckGas(
          BigNumber.from(upkeepId),
          await nelly.getAddress(),
        )

      assert.isTrue(response[0], 'The checkUpkeepSuccess should be true')
      assert.equal(
        response[1],
        '0xabcd',
        'The performData should be forwarded correctly',
      )
      assert.isTrue(
        response[2] > BigNumber.from(0),
        'The gasUsed value must be larger than 0',
      )
    })

    it("returns gas used when registry's checkUpkeep reverts", async () => {
      await registryMockContract.mock.checkUpkeep
        .withArgs(upkeepId, await nelly.getAddress())
        .revertsWithReason('Error')

      const response = await gasUsageWrapper
        .connect(caller)
        .callStatic.measureCheckGas(
          BigNumber.from(upkeepId),
          await nelly.getAddress(),
        )

      assert.isFalse(response[0], 'The checkUpkeepSuccess should be false')
      assert.equal(
        response[1],
        '0x',
        'The performData should be forwarded correctly',
      )
      assert.isTrue(
        response[2] > BigNumber.from(0),
        'The gasUsed value must be larger than 0',
      )
    })
  })

  describe('getKeeperRegistry()', () => {
    it('returns the underlying keeper registry', async () => {
      const registry = await gasUsageWrapper.connect(caller).getKeeperRegistry()
      assert.equal(
        registry,
        registryMockContract.address,
        'The underlying keeper registry is incorrect',
      )
    })
  })
})
