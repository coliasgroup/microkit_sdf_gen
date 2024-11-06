import React, { useState, useEffect } from 'react';
import { Input, Select, Space, Tabs } from 'antd';
import { MemoryEditor } from './pages/memory-editor'
import DeviceTreeViewer from './pages/device-tree-viewer'
import './App.css'
import { DiagramEditor } from './pages/diagram-editor'
import { MemoryRegion } from './utils/element'

const onChange = (key: any) => {}
  
const App = () => {
  const [ deviceTreeJson, setDeviceTreeJson ] = useState(null)
  const [ getDeviceTree, setGetDeviceTree ] = useState(null)
  const [ wasmInstance, setWasmInstance ] = useState(null)
  const [ fileName, setFileName ] = useState('Untitled')
  const [ board, setBoard ] = useState<string>('qemu_arm_virt')
  const [ dtb, setDtb ] = useState<Uint8Array>(null)
  const [ MRs, setMRs] = useState<Array<MemoryRegion>>([])
  const [ devices, setDevices ] = useState([])
  const [ pageSizeOptions, setPageSizeOptions ] = useState([])

  const board_list = [
    { value: 'qemu_arm_virt', label: 'qemu_arm_virt' },
  ]

  const switchBoard = (value: string) => {
    setBoard(value)
  };

  const listDevices = (dt_json, tree_path) => {
    const current_device_path = dt_json.name ? tree_path + '/' + dt_json.name : ''
    const children_devices = dt_json.children ? dt_json.children.map(child_json => {
      return listDevices(child_json, current_device_path)
    }).filter(devices => devices.length) : []

    const devices = children_devices.flat()
    if (dt_json.irq) {
      devices.push({
        path: current_device_path,
        irq: dt_json.irq,
        compatibles: dt_json.compatibles
      })
    }
    return devices
  }

  const readDeviceTree = () => {
    if (wasmInstance == null) {
      return
    }

    const attrJson = {
      board: board,
      dtb: Array.from(dtb),
    }
    const inputString = JSON.stringify(attrJson)
    const inputBuffer = new TextEncoder().encode(inputString)

    const inputPtr = 0
    const resultPtr = inputPtr + inputBuffer.length
    const memory_init = new Uint8Array(wasmInstance.exports.memory.buffer)
    memory_init.set(inputBuffer, inputPtr)

    const ret_len = wasmInstance.exports.fetchInitInfo(inputPtr, inputBuffer.length, resultPtr)

    const memory = new Uint8Array(wasmInstance.exports.memory.buffer)
    const resultString = new TextDecoder().decode(memory.subarray(resultPtr, resultPtr + ret_len))

    const board_info_json = JSON.parse(resultString)
    setDeviceTreeJson(board_info_json.device_tree)
    const devices = listDevices(board_info_json.device_tree, '')
    setDevices(devices)
    const page_size_options = board_info_json.page_size
    setPageSizeOptions(page_size_options)
  }

  const readDtb = () => {
    fetch(board + '.dtb').then(response =>
      response.arrayBuffer()
    ).then(bytes => {
      const typedArray = new Uint8Array(bytes)
      setDtb(typedArray)
    })
  }

  useEffect(() => {
    readDeviceTree()
  }, [dtb, wasmInstance])

  useEffect(() => {
    readDtb()
  }, [board])

  useEffect(() => {
    fetch('gui_sdfgen.wasm').then(response => {
    // fetch('test_gui.wasm').then(response => {
      return response.arrayBuffer()
    }).then(bytes => {
      const typedArray = new Uint8Array(bytes)
      return WebAssembly.instantiate(typedArray, {}).then(result => {
        setWasmInstance(result.instance)
      })
    })
    readDtb()
  }, []);

  return (
    <div className="App">
      <div className="top-bar">LionsOS system composer</div>
      <div className="arch-config-bar">
        <Space wrap>
          FileName:
          <Input value={fileName} onChange={e => setFileName(e.target.value)} suffix=".system.vis"/>
          Board:
          <Select
            defaultValue={board}
            style={{ width: 200 }}
            onChange={switchBoard}
            options={board_list}
          />
        </Space>
      </div>
      <div className='system-container'>
        <Tabs defaultActiveKey="1" items={[
          {
            key: '1',
            label: 'Design',
            children: <DiagramEditor board={board} fileName={fileName} dtb={dtb} devices={devices} MRs={MRs} setMRs={setMRs} wasmInstance={wasmInstance} />,
          },
          {
            key: '2',
            label: 'Memory Regions',
            children: <MemoryEditor MRs={MRs} setMRs={setMRs} pageSizeOptions={pageSizeOptions} />,
          },
          {
            key: '3',
            label: 'Device Tree',
            children: <DeviceTreeViewer deviceTreeJson={deviceTreeJson} />,
          },
        ]} onChange={onChange} />
      </div>
    </div>
  )
}
export default App;
