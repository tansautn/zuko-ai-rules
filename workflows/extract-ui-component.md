---
description: Workflow to extract a section from main_window.ui into a standalone component .ui file
---

# Extract UI Component from main_window.ui

Workflow để phân rã/tách `main_window.ui` thành các component `.ui` độc lập, rồi promote lại trong main.

## Prerequisites

- Component directory đã tồn tại: `app/windows/components/<ComponentName>/`
- Xác định rõ **container widget** cần tách (vd: `tabTasks` QWidget — 1 page của QTabWidget)

## Steps

### 1. Xác định phạm vi cắt

Mở `main_window.ui` trong Qt Designer hoặc text editor. Xác định container widget cần tách.

**Quy tắc**: Container phải là 1 widget hoàn chỉnh (QWidget/QGroupBox/QFrame) có layout riêng. Thường là 1 **page** của QTabWidget hoặc 1 **section** trong QSplitter.

Ví dụ: `<widget class="QWidget" name="tabTasks">` chứa toàn bộ DataTable + action buttons.

### 2. Cut nội dung vào file .ui mới

Tạo file `app/windows/components/<ComponentName>/<ComponentName>.ui` với cấu trúc:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ui version="4.0">
    <author>Zuko</author>
    <class>ComponentName</class>
    <widget class="QWidget" name="ComponentName">
        <property name="windowTitle">
            <string>Component Title</string>
        </property>
        <!-- PASTE NỘI DUNG CỦA CONTAINER Ở ĐÂY -->
        <!-- Giữ nguyên layout, child widgets, properties -->
    </widget>
    <customwidgets>
        <!-- Copy custom widget declarations từ main_window.ui nếu component dùng chúng -->
        <!-- Ví dụ DataTable: -->
        <customwidget>
            <class>DataTable</class>
            <extends>QWidget</extends>
            <header>packages.pdw.datatable</header>
            <container>1</container>
        </customwidget>
    </customwidgets>
    <resources/>
    <connections/>
</ui>
```

**Lưu ý quan trọng:**
- `<class>` và widget `name` phải khớp nhau
- Copy `<customwidgets>` section cho bất kỳ custom widget nào được dùng trong component (DataTable, SmartTimeEditWidget, v.v.)
- Giữ nguyên tên widget (`btnCancelTask`, `tableTasks`...) — chúng sẽ được truy cập qua `WidgetManager` sau compile
- Nếu có `<connections>` liên quan (signal/slot trong .ui), di chuyển chúng sang component .ui

### 3. Cập nhật main_window.ui — Promote widget

Trong `main_window.ui`, **thay thế toàn bộ nội dung** của container widget bằng promoted widget:

**Trước:**
```xml
<widget class="QWidget" name="tabTasks">
    <attribute name="title"><string>Tasks</string></attribute>
    <layout class="QVBoxLayout" name="tasksLayout">
        <!-- 100+ lines of DataTable + buttons -->
    </layout>
</widget>
```

**Sau:**
```xml
<widget class="TaskTableWidget" name="tabTasks">
    <attribute name="title"><string>Tasks</string></attribute>
</widget>
```

Và thêm promoted widget vào `<customwidgets>` section:
```xml
<customwidget>
    <class>TaskTableWidget</class>
    <extends>QWidget</extends>
    <header>app.windows.components.TaskTable</header>
</customwidget>
```

> **Header** phải trỏ tới Python import path của component module (nơi Widget class được export trong `__init__.py`).

### 4. Compile UI

```bash
// turbo
pixi run uic
```

Kiểm tra output: đảm bảo cả component `.py` và `main_window.py` được generate thành công.

### 5. Implement Widget class

Tạo `<ComponentName>Widget.py` theo pattern:

```python
from PySide6.QtWidgets import QWidget
from core import BaseController
from .<ComponentName> import Ui_<ComponentName>

class <ComponentName>Widget(Ui_<ComponentName>, BaseController, QWidget):
    slot_map = {
        # Map button signals → event names
        # 'eventName': ['widgetName', 'signalName'],
    }
    
    def __init__(self, parent=None):
        super().__init__(parent)
        # BaseController calls setupUi + setupHandler automatically
        # Add post-init logic here
```

### 6. Implement Handler class

Tạo `<ComponentName>Handler.py` tại **cùng thư mục** với Widget:

```python
from core.BaseController import BaseCtlHandler

class <ComponentName>Handler(BaseCtlHandler):
    def __init__(self, widgetManager, events):
        super().__init__(widgetManager, events)
    
    def onEventName(self, data=None):
        # Handle button click
        pass
```

> Handler sẽ được auto-discovered bởi `BaseController.setupHandler()` vì cùng module path.

### 7. Create `__init__.py`

```python
from .<ComponentName>Widget import <ComponentName>Widget
from .<ComponentName>Handler import <ComponentName>Handler

__all__ = ['<ComponentName>Widget', '<ComponentName>Handler']
```

### 8. Cleanup MainController

- Remove slot_map entries cho buttons đã chuyển sang component
- Remove signal handler methods đã chuyển sang component
- Remove setupSignalHandlers connections cho signals đã chuyển
- Remove update methods cho table đã chuyển

### 9. Cleanup MainHandler

- Remove handler methods (`onXxx`) cho events đã chuyển sang component handler

### 10. Verify

```bash
// turbo
pixi run uic
```

Chạy app, kiểm tra:
- Component hiển thị đúng layout trong MainWindow
- Buttons hoạt động (signals → handler)
- DataTable hiển thị data đúng

## Checklist

- [ ] `.ui` file tạo xong, có `<customwidgets>` đầy đủ
- [ ] `main_window.ui` đã promote widget + remove nội dung cũ
- [ ] `pixi run uic` compile thành công
- [ ] Widget class implement đúng pattern (Ui → BaseController → QWidget)
- [ ] Handler class auto-discovered thành công
- [ ] `__init__.py` export đúng
- [ ] MainController cleaned up
- [ ] MainHandler cleaned up
- [ ] App chạy đúng
