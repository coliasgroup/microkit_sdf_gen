import { PDComponentInit } from "./os-components/pd"
import { VMComponentInit } from "./os-components/vm"
import { SerialComponentInit } from "./os-components/serial"
import { Graph, Cell, Edge } from '@antv/x6'

const group_registration = {
  'Basic': {
    'PD': PDComponentInit,
    'VM': VMComponentInit,
  },
  'Subsystem': {
    'serial': SerialComponentInit,
  }
}

export const stencilRender = (graph, stencil) => {
  Object.entries(group_registration).map(group => {
    const [group_name, group_items] = group
    const node_list = Object.values(group_items).map(component_init => {
      const node = graph.createNode(component_init.preview_attrs)
      node.data.createNode = component_init.createNode
      return node
    })
    stencil.load(node_list, group_name)
  })
}

export const stencil_group = Object.keys(group_registration).map(key => {
  return {name: key, title: key}
})

export const restoreCell = (graph: Graph, cell: any) => {
  const component_type = cell.data.type == 'sddf_subsystem' ? cell.data.attrs.class : cell.data.type
  if (component_type == 'channel') {
    const edge = graph.addEdge({
      shape: 'edge',
      source: cell.data.source_node_id,
      target: cell.data.target_node_id,
    })
    edge.attr('line/targetMarker', { tagName: 'circle', r: 2 })
    edge.attr('line/sourceMarker', { tagName: 'circle', r: 2 })
    const sourceNode = edge.getSourceNode()
    const targetNode = edge.getTargetNode()
    edge.data = {
      type: 'channel',
      source_node: sourceNode,
      source_end_id: cell.data.source_end_id,
      target_node: targetNode,
      target_end_id: cell.data.target_end_id,
    }
    return
  }

  const component_init_list = Object.assign.apply({}, Object.values(group_registration).map(group => {
    return group
  }))
  const { data, ...rest } = cell
  const new_node = component_init_list[component_type].createNode(null, { ...rest })
  graph.addNode(new_node)
  new_node.data.component.restoreDiagram(graph, data)
}

export const saveCell = (cell: any) => {
  if (cell.shape == 'rect') {
    const { data, attrs, ports, ...rest } = cell
    return {
      ...rest,
      data: cell.data.component.getData()
    }
  } else if (cell.shape == 'edge') {
    return {
      data: {
        type: 'channel',
        source_end_id: cell.data.source_end_id,
        source_node_id: cell.data.source_node.id,
        target_end_id: cell.data.target_end_id,
        target_node_id: cell.data.target_node.id,
      }
    }
  }
}
