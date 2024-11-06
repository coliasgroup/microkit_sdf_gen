import {
  SystemComponentInit,
  SystemComponent,
  DataModel,
  EditableAttrs,
  parseMapJson,
  common_attrs,
  common_ports,
} from "./component-interface";
import { Group } from '../group'
import { Graph } from "@antv/x6";
import { randColor } from '../../utils/helper'
import { SysMapItem } from '../mapping-table'
import { SysIrq } from '../irq-table'
import { getNodeByID, ContiguousIntList } from '../../utils/helper'

interface PDDataModel extends DataModel {
  type: 'PD',
  color: string,
  attrs: {
    name: string,
    priority: number,
    budget: number,
    period: number,
    pp: boolean,
    prog_img: string,
  },
  mappings: SysMapItem[],
  irqs: SysIrq[],
}

export const pd_preview_attrs = {
  ...common_attrs,
  shape: 'rect',
  width: 80,
  height: 40,
  label: 'PD',
  data: {
    name: 'PD',
    cellType: 'group',
  },
  attrs: {
    body: {
    fill: '#efdbff',
    stroke: '#9254de',
    strokeWidth: 1,
    },
  },
}

const group_attrs = {
  ...common_attrs,
  shape: 'rect',
  width: 160,
  height: 80,
  data: {},
  attrs: {
    label: {
      text: 'untitled_pd',
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
      stroke: '#9254de',
      strokeWidth: 1,
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

export const PDComponentInit: SystemComponentInit = {
  preview_attrs: pd_preview_attrs,
  createNode: (subsystem: string | null, attrs?: any) => {
    const group = new Group({ ...group_attrs, ...attrs})
    const new_component = new PDComponent(group.id, subsystem)
    group.data = {
      component: new_component,
      parent: true,
    }
    group.setAttrs({ label: { text: new_component.data.attrs.name } })

    return group
  }
}

var next_id_in_name = 1;

export class PDComponent implements SystemComponent {
  data: PDDataModel = {
    node_id: '',
    type: 'PD',
    color: '#FFFFFF',
    attrs: {
      name: '',
      priority: 0,
      budget: 0,
      period: 0,
      pp: false,
      prog_img: 'default.elf',
    },
    mappings: [],
    irqs: [],
    subsystem: null,
  };

  editable_attrs: EditableAttrs[] = [
    { name: 'name', type: 'string', required: true },
    { name: 'priority', type: 'number', min: 0, max: 255, required: true },
    { name: 'budget', type: 'number', min: 0, max: 1000, required: false },
    { name: 'period', type: 'number', min: 0, max: 1000, required: false },
    { name: 'pp', type: 'boolean', required: true },
    { name: 'prog_img', type: 'string', required: true },
  ];

  constructor(node_id: string, subsystem: string | null) {
    this.data.color = randColor()
    this.data.subsystem = subsystem
    this.data.node_id = node_id
    this.data.attrs.name = 'pd' + next_id_in_name
    next_id_in_name += 1
  }

  public getData = () => {
    return this.data
  }

  public getType = () => {
    return this.data.type
  }

  public getMappings = () => {
    return this.data.mappings
  }

  public getAttrValues = () => {
    return this.data.attrs
  }

  public isPartOfSubsystem = () => {
    return this.data.subsystem != null
  }

  public renderChildrenNodes = (graph: Graph) => {}

  public renderUnchangableNodes = () => {
    return <div style={ {width: '50%', height: '10px', margin: '10px', backgroundColor: this.data.color}}></div>
  }

  // Update style if attributes are modified, e.g. PD names
  // Render children nodes if exist
  public updateData = (graph : Graph, new_data : any) => {
    this.data = {...this.data, ...new_data}
    const this_node = getNodeByID(graph, this.data.node_id)
    if (this_node) {
       this_node.setAttrs({ label: { text: this.data.attrs.name } })
    }
  }

  // Generate JSON for the component
  public getJson = (node?: Group) => {
    var children = []
    if (node) {
      children = node.children?.map(child => {
        return child.data.component.getJson()
      })
    }

    const mappings = parseMapJson(this.data.mappings)

    return {
      ...this.data.attrs,
      children: children ? children : [],
      type: this.data.type,
      maps: mappings,
      irqs: this.data.irqs,
    }
  }

  public saveDiagram = () => {
    return {
      data: this.data
    }
  }

  public restoreDiagram = (graph: Graph, data: any) => {
    const node_id = this.data.node_id
    const subsystem = this.data.subsystem
    this.data.node_id = node_id
    this.data.subsystem = subsystem
    this.updateData(graph, data)
  }
}
