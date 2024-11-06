import ReactDom from 'react-dom'
import { Dropdown } from 'antd'
import { ToolsView, EdgeView } from '@antv/x6'
import type { MenuProps } from 'antd'

export class ContextMenuTool extends ToolsView.ToolItem<
  EdgeView,
  ContextMenuToolOptions
> {
  private timer: number

  private toggleContextMenu(visible: boolean, pos?: { x: number; y: number }) {
    ReactDom.unmountComponentAtNode(this.container)
    document.removeEventListener('mousedown', this.onMouseDown)

    if (visible && pos) {
      ReactDom.render(
        <Dropdown
          open={true}
          trigger={['contextMenu']}
          menu={{ items: this.options.menu }}
          align={{ offset: [pos.x, pos.y] }}
        >
          <span />
        </Dropdown>,
        this.container,
      )
      document.addEventListener('mousedown', this.onMouseDown)
    }
  }

  private onMouseDown = () => {
    this.timer = window.setTimeout(() => {
      this.toggleContextMenu(false)
    }, 200)
  }

  private onContextMenu({ e }: { e: MouseEvent }) {
    if (this.timer) {
      clearTimeout(this.timer)
      this.timer = 0
    }
    this.toggleContextMenu(true, { x: e.clientX, y: e.clientY })
  }

  delegateEvents() {
    this.cellView.on('cell:contextmenu', this.onContextMenu, this)
    return super.delegateEvents()
  }

  protected onRemove() {
    this.cellView.off('cell:contextmenu', this.onContextMenu, this)
  }
}

export interface ContextMenuToolOptions extends ToolsView.ToolItem.Options {
  menu: MenuProps['items']
}