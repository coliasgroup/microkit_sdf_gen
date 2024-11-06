import { useState, useEffect } from 'react';
import init, { greet } from "validator-wasm"
import { PDComponent } from "./os-components/pd"

const SDFGenerator = ({ globalGraph, toGenerateSDF, setToGenerateSDF, setSDFText, MRs, board, dtb, wasmInstance }) => {
  const [drivers, setDrivers] = useState([])
  const [deviceClass, setDeviceClass] = useState([])
  const [SDF, setSDF] = useState("")

  const sDDFURL = `https://raw.githubusercontent.com/au-ts/sddf/862feed2485d5a6f5f31f80664dd6ad5374b757c/`
  const driver_paths = [
    {class: "network", path: "drivers/network/imx/config.json"},
    {class: "network", path: "drivers/network/meson/config.json"},
    {class: "network", path: "drivers/network/virtio/config.json"},
    {class: "serial", path: "drivers/serial/meson/config.json"},
    {class: "serial", path: "drivers/serial/imx/config.json"},
    {class: "serial", path: "drivers/serial/arm/config.json"},
  ]

  const driver_configs = [
    {class: "serial", path: "sddf_configs/serial_arm.json"},
    {class: "serial", path: "sddf_configs/serial_arm.json"},
  ]


  const device_class_paths = [
    {class: "network", path: "network/config.json"},
    {class: "network", path: "serial/config.json"},
  ]

  const getMRJson = (MRs) => {
    if (MRs == null) return []

    const mrs = MRs.map(MR => {
      const { nodes, ...rest } = MR
      return rest
    })

    return mrs
  }

  const getChannelJson = (edges) => {
    if (edges == null) return []

    const channels = edges.map(edge => {
      const pd1 = edge.data.source_node?.data.component
      const pd2 = edge.data.target_node?.data.component

      if (pd1.getType() == 'sddf_subsystem' && pd2.getType() == 'PD') {
        return ''
      }
      if (pd2.getType() == 'sddf_subsystem' && pd1.getType() == 'PD') {
        return ''
      }

      return {
        pd1: pd1.getAttrValues().name,
        pd2: pd2.getAttrValues().name,
        pd1_end_id: parseInt(edge.data.source_end_id),
        pd2_end_id: parseInt(edge.data.target_end_id),
      }
    }).filter(channel => channel != '')
    return channels
  }

  const generateSDF = () => {
    const attrJson = {
      board: board,
      dtb: Array.from(dtb),
      drivers: drivers,
      deviceClasses: deviceClass,
      mrs: [],
      pds: [],
      channels: [],
      sddf_subsystems: [],
    }

    const PDs = globalGraph?.getNodes().filter(node => {
      return node.data.component.getType() == "PD"
    }).filter(node => {
      const component : PDComponent = node.data.component
      return node.parent == null || component.isPartOfSubsystem()
    })
    attrJson.pds = PDs?.map(pd => pd.data.component.getJson(pd)) ?? []

    const sddf_subsystems = globalGraph?.getNodes().filter(node => node.data.component.getType() == 'sddf_subsystem')
    attrJson.sddf_subsystems = sddf_subsystems?.map(subsystem => subsystem.data.component.getJson(subsystem)) ?? []

    const channels = globalGraph?.getEdges().filter(edge => edge.data.type == "channel")
    attrJson.channels = getChannelJson(channels)

    attrJson.mrs = getMRJson(MRs)
    console.log(attrJson)

    const inputString = JSON.stringify(attrJson)
    const inputBuffer = new TextEncoder().encode(inputString)
    
    const inputPtr = 0
    const resultPtr = inputPtr + inputBuffer.length
    const memory_init = new Uint8Array(wasmInstance.exports.memory.buffer)
    memory_init.set(inputBuffer, inputPtr)

    const ret_len = wasmInstance.exports.jsonToXml(inputPtr, inputBuffer.length, resultPtr)
    console.log(ret_len)
    
    const memory = new Uint8Array(wasmInstance.exports.memory.buffer)
    const resultString = new TextDecoder().decode(memory.subarray(resultPtr, resultPtr + ret_len))
    console.log("Result:\n", resultString)

    setSDFText(resultString)
    setSDF(resultString)
    setToGenerateSDF(false)
  }

  const readDeviceConfig = async (config_paths, setStateFunc) => {
    const fetchFileContent = async (entry) => {
      try {
        const response = await fetch(entry.path)
        if (response.ok) {
          return {class: entry.class, content: await response.text()};
        }
        return
      } catch (err) {
        console.log(err)
        return
      }
    };

    const fetchAllFiles = async () => {
      try {
        const contents = await Promise.all(config_paths.map(fetchFileContent));
        setStateFunc(contents.filter(entry => entry != null))
      } catch (err) {
        console.log(err.message)
      }
    }

    fetchAllFiles()
  }

  useEffect(() => {
    readDeviceConfig(driver_configs, setDrivers)
  }, [])

  useEffect(() => {
    if (toGenerateSDF) {
      generateSDF()
      setToGenerateSDF(false)
    }
  }, [toGenerateSDF])

  return (
    <>
    </>
  )
}

export default SDFGenerator;
