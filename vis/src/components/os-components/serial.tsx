import {
  SystemComponentInit,
  SystemComponent,
  DataModel,
  EditableAttrs,
  common_attrs,
  common_ports
} from "./component-interface";
import { Group } from '../group'
import { Graph } from "@antv/x6";
import { PDComponentInit } from "./pd"
import { getComponentByID, getNodeByID } from '../../utils/helper'

interface SerialDataModel extends DataModel {
  type: 'sddf_subsystem',
  attrs: {
    class: string,
    clients: string[],
    device_node: string,
    driver_name: string,
    serial_mux_tx: string,
    serial_mux_rx: string,
    data_region_size: number,
  },
  children: {
      driver: string | null,
      mux_tx: string | null,
      mux_rx: string | null,
  }
}

const serial_preview_attrs = {
  ...common_attrs,
  shape: 'rect',
  width: 80,
  height: 40,
  label: 'Serial',
  data: {
    name: 'Serial',
    cellType: 'group',
  },
  attrs: {
    text: {
      textAnchor: "middle",
    },
    body: {
      fill: '#ffd591',
      stroke: '#ffa940',
      strokeWidth: 1,
    },
  },
}

const group_attrs = {
  ...common_attrs,
  shape: 'rect',
  width: 400,
  height: 240,
  data: {},
  attrs: {
    label: {
      text: 'Serial System',
      fontSize: 16,
      fill: "#000000",
    },
    text: {
      textAnchor: "left",
      x: 0,
      y: 12,
    },
    body: {
      fill: '#efdbff',
      stroke: '#ffffff',
      strokeWidth: 1,
      rx: 6,
      ry: 6,
    },
  },
  ports: {
    groups: common_ports.ports.groups,
    items: [{
      id: 'port_1',
      group: 'bottom',
      attrs: {
        circle: {
          magnet: true,
          stroke: '#8f8f8f',
          r: 5,
        },
      },
    }],
  }
}

export const SerialComponentInit: SystemComponentInit = {
  preview_attrs: serial_preview_attrs,
  createNode: (subsystem: string | null, attrs?: any) => {
    const group = new Group({ ...group_attrs, ...attrs })
    const new_component = new SerialComponent(group.id)
    group.data = {
      component: new_component,
      parent: true,
    }

    return group
  }
}

export class SerialComponent implements SystemComponent {

  data: SerialDataModel = {
    node_id: '',
    type: 'sddf_subsystem',
    attrs: {
      class: 'serial',
      clients: [],
      device_node: '',
      driver_name: 'serial_driver',
      serial_mux_tx: 'serial_mux_tx',
      serial_mux_rx: 'serial_mux_rx',
      data_region_size: 0x1000,
    },
    subsystem: null,
    children: {
      driver: null,
      mux_tx: null,
      mux_rx: null,
    }
  };

  editable_attrs: EditableAttrs[] = [
    { name: 'driver_name', type: 'string', required: true },
    { name: 'driver_node', type: 'string', required: true },
    { name: 'serial_mux_tx', type: 'string', required: true },
    { name: 'serial_mux_rx', type: 'string', required: true },
    { name: 'data_region_size', type: 'number', required: true }
  ];

  constructor(node_id: string) {
    this.data.node_id = node_id
  }

  public getData = () => {
    return this.data
  }

  public getType = () => {
    return this.data.type
  }

  public getMappings = () => {
    return []
  }

  public getAttrValues = () => {
    return this.data.attrs
  }

  public addClient = (node_id: string) => {
    this.data.attrs.clients.push(node_id)
  }

  private syncChildrenData = (graph: Graph) => {

    const driver_component = getComponentByID(graph, this.data.children.driver)
    driver_component.updateData(graph, {
      attrs: {...driver_component.getAttrValues(), name: this.data.attrs.driver_name},
      subsystem: this.data.node_id,
    })

    const mux_tx_component = getComponentByID(graph, this.data.children.mux_tx)
    mux_tx_component.updateData(graph, {
      attrs: {...mux_tx_component.getAttrValues(), name: this.data.attrs.serial_mux_tx},
      subsystem: this.data.node_id,
    })

    const mux_rx_component = getComponentByID(graph, this.data.children.mux_rx)
    mux_rx_component.updateData(graph, {
      attrs: {...mux_rx_component.getAttrValues(), name: this.data.attrs.serial_mux_rx},
      subsystem: this.data.node_id,
    })
  }

  public renderChildrenNodes = (graph: Graph) => {
    console.log(this.data.children)
    if (this.data.children.driver) {
      return
    }

    const node = graph.getNodes().find(node => node.id === this.data.node_id)
    const serial_system = node
    const {x, y} = serial_system.getPosition()

    // Add serial driver
    const serial_driver = PDComponentInit.createNode(this.data.node_id)
    serial_driver.position(x + 220, y + 80)
    serial_system.addChild(serial_driver)
    this.data.children.driver = serial_driver.id

    // Add mux_tx PD
    const mux_tx = PDComponentInit.createNode(this.data.node_id)
    mux_tx.position(x + 20, y + 40)
    serial_system.addChild(mux_tx)
    serial_system.data.mux_tx = mux_tx.id
    this.data.children.mux_tx = mux_tx.id

    // Add mux_rx PD
    const mux_rx = PDComponentInit.createNode(this.data.node_id)
    mux_rx.position(x + 20, y + 140)
    serial_system.addChild(mux_rx)
    serial_system.data.mux_rx = mux_rx.id
    this.data.children.mux_rx = mux_rx.id

    this.syncChildrenData(graph)
  }

  public renderUnchangableNodes = () => {
    return <></>
  }

  // Update style if attributes are modified, e.g. PD names
  // Render children nodes if exist
  public updateData = (graph: Graph, new_data : any) => {
    this.data = {...this.data, ...new_data}
    this.syncChildrenData(graph)
  }

  // Generate JSON for the component
  public getJson = () => {
    return this.data.attrs
  }

  public saveDiagram = () => {
    return {
      data: this.data
    }
  }

  public restoreDiagram = (graph: Graph, data: any) => {
    this.data.node_id = data.node_id
    this.data.subsystem = data.subsystem
    this.updateData(graph, data)
    this.syncChildrenData(graph)
  }
}
