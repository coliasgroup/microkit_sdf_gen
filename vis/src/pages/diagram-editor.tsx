import React, { useEffect, useState } from 'react'
import { Modal } from 'antd'
import { Graph, Cell, Edge } from '@antv/x6'
import { ERLayout } from '@antv/layout'
import { Stencil } from '@antv/x6-plugin-stencil'
import { Snapline } from '@antv/x6-plugin-snapline'
import { Toolbar } from '@antv/x6-react-components'
import { Group } from '../components/group'
import NodeEditor from '../components/node-editor'
import { stencilRender, stencil_group } from '../components/nodes'
import MemoryManager from '../components/memory-manager'
import ChannelEditor from '../components/channel-editor'
import TemplateList from '../components/template-list'
import { MemoryRegion } from '../utils/element'
import { channelLabelConfig, getValidEndID, randColor, closestBorder, reassignEdgesForComponent } from '../utils/helper'
import SDFGenerator from '../components/sdf-generator'
import '@antv/x6-react-components/es/menu/style/index.css'
import '@antv/x6-react-components/es/toolbar/style/index.css'
import '../App.css'
import {
  ZoomInOutlined,
  ZoomOutOutlined,
  RedoOutlined,
  UndoOutlined,
  DeleteOutlined,
  FileImageOutlined,
  SaveOutlined,
  FolderOpenOutlined,
  EditOutlined,
  DownloadOutlined,
  UploadOutlined,
} from '@ant-design/icons'
import { SystemComponent } from '../components/os-components/component-interface'
import { XMLParser } from 'fast-xml-parser'
import { loadDiagramFromXml } from '../utils/translator'
import { restoreCell, saveCell } from '../components/nodes'

const Item = Toolbar.Item             // eslint-disable-line
const ToolbarGroup = Toolbar.Group    // eslint-disable-line

export const DiagramEditor = ({ board, fileName, dtb, devices, MRs, setMRs, wasmInstance }) => {
  const refGraphContainer = React.createRef<HTMLDivElement>()
  const refStencilContainer = React.createRef<HTMLDivElement>()
  const refTextarea = React.useRef<HTMLTextAreaElement>()
  const [ globalGraph, setGlobalGraph ] = useState<Graph>(null)
  const [ SDFEditorOpen, setSDFEditorOpen ] = useState(false)
  const [ templateListOpen, setTemplateListOpen ] = useState(false)
  const [ nodeEditorOpen, setNodeEditorOpen ] = useState(false)
  const [ channelEditorOpen, setChannelEditorOpen ] = useState(false)
  const [ currentEdgeID, setCurrentEdgeID ] = useState('')
  const [ currentNodeID, setCurrentNodeID ] = useState('')
  const [ toGenerateSDF, setToGenerateSDF ] = useState<boolean>(false)
  const [ SDFText, setSDFText ] = useState('')
  const [ MRSDF, setMRSDF ] = useState<Array<any>>([])

  var ctrlPressed = false

  const graph_config = {
    panning: true,
    mousewheel: true,
    background: {
      color: '#F2F7FA',
    },
    grid: {
      visible: true,
      type: 'doubleMesh',
      args: [
        {
          color: '#eee',
          thickness: 1,
        },
        {
          color: '#ddd',
          thickness: 1,
          factor: 4,
        },
      ],
    },
    connecting: {
      allowEdge: true,
      allowBlank: true,
      allowPort: false,
      allowMulti: false,
      allowLoop: false,
      router: 'manhattan',
    },
    embedding: {
      enabled: true,
      findParent({ node }) {
        const bbox = node.getBBox()
        return this.getNodes().filter((node) => {
          const data = node.getData()
          if (data && data.parent) {
            const targetBBox = node.getBBox()
            return bbox.isIntersectWithRect(targetBBox)
          }
          return false
        })
      },
    },
    highlighting: {
      embedding: {
        name: 'stroke',
        args: {
          padding: -1,
          attrs: {
            stroke: '#73d13d',
          },
        },
      },
    },
  }

  const stencil_config = {
    title: 'Components',
    search(cell, keyword) {
      return cell.shape.indexOf(keyword) !== -1
    },
    placeholder: 'Search by component name',
    notFoundText: 'Not Found',
    collapsable: false,
    stencilGraphHeight: 0,
    groups: stencil_group,
    getDropNode(node) {
      return node.data?.createNode()
    },
  }

  const openExampleDiagram = async() => {
    // fetch('test.system.vis').then(response =>
    fetch('examples/wordle.system').then(response =>
      response.arrayBuffer()
    ).then(bytes => {
      const typedArray = new Uint8Array(bytes)
      var enc = new TextDecoder("utf-8")
      const jsonString = enc.decode(typedArray)
      const json = JSON.parse(jsonString)

      const load_order = {
        "PD": 0,
        "VM": 1,
        "sddf_subsystem": 2,
        "channel": 3,
      }
      const cells = json.cells.sort((a, b) => {
        return load_order[a.data.type] - load_order[b.data.type]
      })
      cells.map(cell => {
        restoreCell(globalGraph, cell)
      })
      reassignEdgesForComponent(globalGraph)
      console.log(json.mrs)
      setMRs(json.mrs)
    })
  }

  const saveDiagram = async () => {
    const graphObject = globalGraph.toJSON()
    const cells = graphObject.cells.map(cell => {
      return saveCell(cell)
    })
    const diagram_content = JSON.stringify({
      cells: cells,
      mrs: MRs
    })

    const fileFullName = fileName + ".system.vis";

    try {
      // Open the directory picker
      const dirHandle = await window.showDirectoryPicker();

      // Create a new file handle in the selected directory
      const fileHandle = await dirHandle.getFileHandle(fileFullName, { create: true });

      // Create a writable stream
      const writable = await fileHandle.createWritable();

      // Write the content to the file
      await writable.write(diagram_content);

      // Close the writable stream
      await writable.close();

      alert('File saved successfully!');
    } catch (error) {
      console.error('Error saving file:', error);
    }
  }

  const openDiagram = async () => {
    try {
      // Open the file picker
      const [fileHandle] = await window.showOpenFilePicker();
      const file = await fileHandle.getFile();
      const fileText = await file.text();
      const json = JSON.parse(fileText)

      const load_order = {
        "PD": 0,
        "VM": 1,
        "sddf_subsystem": 2,
        "channel": 3,
      }
      const cells = json.cells.sort((a, b) => {
        return load_order[a.data.type] - load_order[b.data.type]
      })
      cells.map(cell => {
        restoreCell(globalGraph, cell)
      })
      reassignEdgesForComponent(globalGraph)
      setMRs(json.mrs)
    } catch (error) {
      console.error('Error reading file:', error);
    }
  };

  const openSDFEditor = () => {
    setSDFEditorOpen(true)
    setToGenerateSDF(true)
  }

  const openSDF = async () => {
    try {
      // Open the file picker
      const [fileHandle] = await window.showOpenFilePicker()
      const file = await fileHandle.getFile()
      const fileText = await file.text()

      loadDiagramFromXml(globalGraph, fileText, updateMappings)
      reassignEdgesForComponent(globalGraph)
    } catch (error) {
      console.error('Error reading file:', error);
    }
  }

  const openTemplateList = () => {
    const PDs = globalGraph.getCells().filter(cell => cell.data.type === 'PD')
    const PDNodes = PDs?.map(PD => {return {"name": PD.data.attrs.name, "node_id": PD.id}})
    setTemplateListOpen(true)
  }

  const updateMappings = (cached_mrs?) => {
    const mrs = cached_mrs ? cached_mrs : MRs
    const nodes = globalGraph.getNodes()
    const newMRs = mrs.map((MR) => {

      const new_mappings = nodes.map((node) => {
        const component = node.data.component
        const node_mappings = component?.getMappings().map(mapping => mapping.mr)
        if (node_mappings.includes(MR.name)) {
          return node.id
        }
        return ''
      }).filter(node_id => node_id !== '')

      return { ...MR, nodes: new_mappings }
    })
    console.log(newMRs)
    setMRs(newMRs)
  }

  const getNodeData = (node_id : string) => {
    const node = globalGraph?.getNodes().find(node => node.id === node_id)
    if (node?.data.subsystem) {
      const subsystem = globalGraph?.getNodes().find(node => node.id === node.data.subsystem)
      return subsystem?.data
    }
    return node?.data
  }

  const updateNodeData = (node_id : string, new_data : any) => {
    const node = globalGraph?.getNodes().find(node => node.id === node_id)

    if (node) {
      // Update data
      node.data = new_data
      // Update the label displayed on the corresponding node
      node.setAttrs({ label: { text: node.data.attrs.name } })
      // Update data and colour of memory regions
      updateMappings()
    } else {
      console.log("Invalid node_id")
    }
  }

  const getEdgeData = (edge_id : string) => {
    const edge = globalGraph?.getEdges().find(edge => edge.id === edge_id)
    return edge?.data
  }

  const updateEdgeData = (edge_id : string, new_data : any) => {
    const edge = globalGraph?.getEdges().find(edge => edge.id === edge_id)
    if (edge) {
      edge.data.source_end_id = new_data.source_end_id
      edge.data.target_end_id = new_data.target_end_id
    } else {
      console.log("Invalid edge_id")
    }
  }

  const updateIRQPosition = (edge : Edge, direction : string, portPosition : { x: number, y: number }) => {
    const irq_len = 40
    if (direction === 'left') {
      edge.prop('target', { x: portPosition.x - irq_len, y: portPosition.y})
    } else if (direction === 'right') {
      edge.prop('target', { x: portPosition.x + irq_len, y: portPosition.y })
    } else if (direction === 'top') {
      edge.prop('target', { x: portPosition.x, y: portPosition.y - irq_len})
    } else if (direction === 'bottom') {
      edge.prop('target', { x: portPosition.x, y: portPosition.y + irq_len})
    }
  }

  const updateIRQsPosition = (node_id : string, graph : Graph) => {
    graph.getEdges().map(edge => {
      if (edge.data.type !== 'irq') return

      if (edge.getSourceNode()?.id === node_id) {
        const sourceNode = edge.getSourceNode()
        const edge_type = edge.data.type
        
        if (edge_type === 'irq') {
          const port = sourceNode.getPorts().find(port => port.id === sourceNode.id + edge.id)
          const portPosition = edge.getSourcePoint()
          updateIRQPosition(edge, port.group, portPosition)
        }
      } else if (edge.getTargetNode()?.id === node_id) {
        const sourceNode = edge.getTargetNode()
        const edge_type = edge.data.type
  
        if (edge_type === 'irq') {
          const port = sourceNode.getPorts().find(port => port.id === sourceNode.id + edge.id)
          const portPosition = edge.getTargetPoint()
          updateIRQPosition(edge, port.group, portPosition)
        }
      }

    })
  }

  useEffect(() => {
    const graph = new Graph({
      ...graph_config,
      container: refGraphContainer.current,
    })
    setGlobalGraph(graph)
  
    graph.use(
      new Snapline({
        enabled: true,
        sharp: true,
      }),
    )

    const stencil = new Stencil({
      ...stencil_config,
      target: graph,
    })

    refStencilContainer.current.appendChild(stencil.container)

    stencilRender(graph, stencil)

    graph.on('node:dblclick', ({ node, e }) => {
      setCurrentNodeID(node.id)
      setNodeEditorOpen(true)
      e.stopPropagation()
    })

    graph.on('node:mouseenter', ({ node }) => {
      // node.setZIndex(999)
      node.addTools({
        name: 'button-remove',
        args: {
          x: '100%',
          y: 0,
          offset: { x: -10, y: 10 },
          onClick(t) {
            // source code of built-in button-remove
            var e=t.view, n=t.btn
            n.parent.remove()
            e.cell.remove({ui:!0, toolId:n.cid})
          }
        },
      })
    })
    
    graph.on('node:mouseleave', ({ node }) => {
      // node.setZIndex(1)
      node.removeTools()
    })

    graph.on('node:mouseenter', ({ node }) => {
      node.toFront({ deep: true })
    })

    graph.on('node:mouseleave', ({ node }) => {
      if (node.parent == null) {
        node.toBack({ deep: true })
      } else {
        node.parent.toBack({ deep: true })
      }
    })

    graph.on('node:embedding', ({ e }: { e }) => {
      ctrlPressed = e.metaKey || e.ctrlKey
    })
    
    graph.on('node:embedded', ({ node, currentParent }) => {
      ctrlPressed = false
      currentParent.toBack({ deep: true })
      var topParent : Cell = currentParent
      while (topParent.parent) {
        topParent = topParent.parent
      }
      topParent.toBack({ deep: true })
    })

    graph.on('node:change:size', ({ node, options }) => {
      if (options.skipParentHandler) {
        return
      }
    
      const children = node.getChildren()
      if (children && children.length) {
        node.prop('originSize', node.getSize())
      }

      updateIRQsPosition(node.id, graph)
    })

    graph.on('node:collapse', ({ node }: { node: Group }) => {
      node.toggleCollapse()
      const collapsed = node.isCollapsed()
      const collapse = (parent: Group) => {
        const cells = parent.getChildren()
        if (cells) {
          cells.forEach((cell) => {
            if (collapsed) {
              cell.hide()
            } else {
              cell.show()
            }
    
            if (cell instanceof Group) {
              if (!cell.isCollapsed()) {
                collapse(cell)
              }
            }
          })
        }
      }
    
      collapse(node)
    })

    graph.on('node:added', ({ node }) => {
      if (node.children == null) {
        node.data.component.renderChildrenNodes(graph)
      }
    })

    const embedPadding = 20
    graph.on('node:change:position', ({ node, options }) => {
      reassignEdgesForComponent(graph)

      if (options.skipParentHandler || ctrlPressed) {
        return
      }
    
      const children = node.getChildren()
      if (children && children.length) {
        node.prop('originPosition', node.getPosition())
      }
    
      const parent : Group = node.getParent()
      if (parent && parent.isNode()) {
        let originSize = parent.prop('originSize')
        if (originSize == null) {
          originSize = parent.getSize()
          parent.prop('originSize', originSize)
        }
    
        let originPosition = parent.prop('originPosition')
        if (originPosition == null) {
          originPosition = parent.getPosition()
          parent.prop('originPosition', originPosition)
        }
    
        let x = originPosition.x
        let y = originPosition.y
        let cornerX = originPosition.x + originSize.width
        let cornerY = originPosition.y + originSize.height
        let hasChange = false
    
        const children = parent.getChildren()
        if (children) {
          children.forEach((child) => {
            const bbox = child.getBBox().inflate(embedPadding)
            const corner = bbox.getCorner()
    
            if (bbox.x < x) {
              x = bbox.x
              hasChange = true
            }
    
            if (bbox.y < y) {
              y = bbox.y
              hasChange = true
            }
    
            if (corner.x > cornerX) {
              cornerX = corner.x
              hasChange = true
            }
    
            if (corner.y > cornerY) {
              cornerY = corner.y
              hasChange = true
            }
          })
        }
    
        if (hasChange && parent.isCollapsed() == false) {
          parent.prop(
            {
              position: { x, y },
              size: { width: cornerX - x, height: cornerY - y },
            },
            { skipParentHandler: true },
          )
        }
      }
    })

    graph.on('edge:mouseenter', ({ edge }) => {
      edge.addTools([
        {
          name: 'source-arrowhead',
        },
        {
          name: 'target-arrowhead',
        },
        {
          name: 'button-remove',
          args: {distance: '50%'}
        }
      ])

      edge.setLabels(channelLabelConfig(edge.data?.source_end_id, edge.data?.target_end_id))
    })

    graph.on('edge:mouseleave', ({ edge }) => {
      edge.removeTools()
      edge.setLabels({})
    })

    graph.on('edge:mouseup', ({ edge }) => {
      const old_source_node = edge.data?.source_node
      const old_target_node = edge.data?.target_node

      const new_source_node = edge.getSourceNode()
      const new_target_node = edge.getTargetNode()

      // TODO: replace all '1' with getFreeEndID()
      edge.attr('line/targetMarker', { tagName: 'circle', r: 2 })
      edge.attr('line/sourceMarker', { tagName: 'circle', r: 2 })
      if (new_source_node && new_target_node) {
        if (old_source_node == null && old_target_node == null) {
          edge.data = {
            type: 'channel',
            source_node: new_source_node,
            source_end_id: '1',
            target_node: new_target_node,
            target_end_id: '1',
          }
        } else if (new_source_node != old_source_node) {
          old_source_node?.removePort(old_source_node.id + edge.id)
          edge.setSource(new_source_node)
          edge.data.source_node = new_source_node
          // TODO: assign a new channel id
        } else if (new_target_node != old_target_node) {
          old_target_node?.removePort(old_target_node.id + edge.id)
          edge.setTarget(new_target_node)
          edge.data.target_node = new_target_node
          // TODO: assign a new channel id
        }
        const sourceComponent = new_source_node.data.component
        const targetComponent = new_target_node.data.component
        if (sourceComponent.getType() == 'sddf_subsystem' && targetComponent.getType() == 'PD') {
          // TODO: pass node_id to client array, and get the pd_name when generating SDF
          sourceComponent.addClient(targetComponent.getAttrValues().name)
        }
        if (sourceComponent.getType() == 'PD' && targetComponent.getType() == 'sddf_subsystem') {
          // TODO: pass node_id to client array, and get the pd_name when generating SDF
          targetComponent.addClient(sourceComponent.getAttrValues().name)
        }
      } else if (!new_source_node && new_target_node && old_source_node) {
        // Reset source
        old_source_node?.removePort(old_source_node.id + edge.id)
        edge.setSource(old_source_node)
        
      } else if (new_source_node && !new_target_node && old_target_node) {
        // Reset target
        old_target_node?.removePort(old_target_node.id + edge.id)
        edge.setTarget(old_target_node)

      } else {
        // remove edge
        graph.removeEdge(edge.id)
      }

      reassignEdgesForComponent(graph)
    })

    graph.on('edge:dblclick', ({ edge }) => {
      setCurrentEdgeID(edge.id)
      setChannelEditorOpen(true)
    })

  }, [])

  useEffect(() => {
    const parser = new XMLParser({ignoreAttributes: false, attributeNamePrefix : ""})
    const parsedData = parser.parse(SDFText)

    // TODO: update MRs
    const newMRSDF = parsedData.system?.memory_region ?? []
    setMRSDF([].concat(newMRSDF))

    // TODO: update IRQs

    // TODO: update mappings
  }, [SDFText])

  return (
    <div>
      <MemoryManager MRSDF={MRSDF} MRs={MRs} setMRs={setMRs} getNodeData={getNodeData} graph={globalGraph} />
      <Toolbar className="toolbar" >
        <ToolbarGroup>
          <Item name="zoomIn" tooltip="Zoom In (Cmd +)" disabled={true} icon={<ZoomInOutlined />} />
          <Item name="zoomOut" tooltip="Zoom Out (Cmd -)" disabled={true} icon={<ZoomOutOutlined />} />
        </ToolbarGroup>
        <ToolbarGroup>
          <Item name="undo" tooltip="Undo (Cmd + Z)" disabled={true} icon={<UndoOutlined />} />
          <Item name="redo" tooltip="Redo (Cmd + Shift + Z)" disabled={true} icon={<RedoOutlined />} />
        </ToolbarGroup>
        <ToolbarGroup>
          <Item name="previewDiagram" icon={<FileImageOutlined />} disabled={true} tooltip="Preview Diagram"></Item>
          <Item name="uploadeSDF" icon={<FolderOpenOutlined />} tooltip="Open Diagram" onClick={openDiagram}></Item>
          <Item name="downloadDiagram" icon={<SaveOutlined />} tooltip="Save Diagram" onClick={saveDiagram}></Item>
        </ToolbarGroup>
        <ToolbarGroup>
          <Item name="editSDF" icon={<EditOutlined />} tooltip="Edit SDF" onClick={openSDFEditor}></Item>
          <Item name="uploadeSDF" icon={<UploadOutlined />} tooltip="Upload SDF" onClick={openSDF}></Item>
          <Item name="downloadTemplates" icon={<DownloadOutlined />} disabled={true} tooltip="Download Templates" onClick={openTemplateList}></Item>
        </ToolbarGroup>
      </Toolbar>
      <div className="stencil-app">
        <div className="app-stencil" ref={refStencilContainer} />
        <div className="app-content" ref={refGraphContainer} />
      </div>
      <NodeEditor
        graph={globalGraph}
        node_id={currentNodeID}
        nodeEditorOpen={nodeEditorOpen}
        setNodeEditorOpen={setNodeEditorOpen}
        devices={devices}
        MRs={MRs}
        updateMappings={updateMappings}
        />
      <ChannelEditor
        graph={globalGraph}
        channelEditorOpen={channelEditorOpen}
        setChannelEditorOpen={setChannelEditorOpen}
        edge_id={currentEdgeID}
        getEdgeData={getEdgeData}
        updateEdgeData={updateEdgeData}
        getNodeData={getNodeData} />
      <Modal
        title="Modal 1000px width"
        centered
        forceRender
        open={SDFEditorOpen}
        onOk={() => setSDFEditorOpen(false)}
        onCancel={() => setSDFEditorOpen(false)}
        width={1000}
      >
        <textarea
          ref={refTextarea}
          value={SDFText}
          onChange={() => console.log('111')}
          style={ {width: '100%', height: '500px'} }>
        </textarea>
      </Modal>
      <TemplateList templateListOpen={templateListOpen} setTemplateListOpen={setTemplateListOpen} graph={globalGraph}></TemplateList>
      <SDFGenerator globalGraph={globalGraph} toGenerateSDF={toGenerateSDF} setToGenerateSDF={setToGenerateSDF} setSDFText={setSDFText} MRs={MRs} board={board} dtb={dtb} wasmInstance={wasmInstance} />
    </div>
  )
}
