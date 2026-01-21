---
trigger: model_decision
description: Service Locator usage, Global vs Scoped Services, and Network Manager integration rules
globs: **/*.py
---

# Service Locator & Network Manager Rules

## **Service Locator Usage**

### **Accessing Services**

- **Always use QtAppContext to access services:**
  ```python
  # ✅ DO: Access services via QtAppContext
  from core.QtAppContext import QtAppContext
  
  ctx = QtAppContext.globalInstance()
  config = ctx.config
  publisher = ctx.publisher
  networkManager = ctx.getService('network')
  taskManager = ctx.getService('task_manager')
  ```

  ```python
  # ❌ DON'T: Direct instantiation of core services
  from core.Config import Config
  config = Config()  # Wrong! Use ctx.config instead
  ```

### **Creating Custom Services**

- **Register global services during bootstrap or initialization:**
  ```python
  # ✅ DO: Register custom global service
  ctx = QtAppContext.globalInstance()
  myService = MyCustomService()
  ctx.registerService('my_service', myService)
  
  # Later access it
  myService = ctx.getService('my_service')
  ```

---

## **Global vs Scoped Services**

### **Global Services (Singletons)**

- **Use for application-wide shared resources:**
  - Config, Publisher, NetworkManager, TaskManager
  - Database connections, API clients
  - Cache managers, Logger instances

- **Registration:**
  ```python
  # ✅ DO: Register global service once
  ctx.registerService('api_client', ApiClient())
  ```

- **Access:**
  ```python
  # ✅ DO: Access anywhere in the app
  apiClient = ctx.getService('api_client')
  ```

### **Scoped Services (Task/Job-specific)**

- **Use for resources tied to a specific task/job lifecycle:**
  - Browser instances (ChromeBrowserService, PlaywrightBrowserService)
  - Temporary file handlers
  - Task-specific API sessions
  - Any resource that needs cleanup after task completion

- **Registration with task UUID:**
  ```python
  # ✅ DO: Register scoped service with task UUID
  def executeTask(self):
      ctx = QtAppContext.globalInstance()
      taskId = self.uuid  # Task UUID as scope tag
      
      # Create and register scoped services
      browser = ChromeBrowserService()
      ctx.registerScopedService(taskId, browser)
      
      fileHandler = TempFileHandler()
      ctx.registerScopedService(taskId, fileHandler)
      
      try:
          # Execute task logic
          browser.navigate('https://example.com')
          # ...
      finally:
          # CRITICAL: Always cleanup scoped services
          ctx.releaseScope(taskId)
  ```

- **Automatic cleanup:**
  ```python
  # ServiceLocator will automatically call cleanup()/close()/dispose()
  # on all scoped instances when releaseScope() is called
  
  class ChromeBrowserService:
      def cleanup(self):
          """Called automatically by ServiceLocator.releaseScope()"""
          self.driver.quit()
          logger.info("Browser cleaned up")
  ```

### **Best Practices**

- **Always use try-finally for scoped services:**
  ```python
  # ✅ DO: Ensure cleanup even on exceptions
  taskId = self.uuid
  ctx.registerScopedService(taskId, browser)
  try:
      # Task logic
      pass
  finally:
      ctx.releaseScope(taskId)
  ```

- **Implement cleanup methods in scoped services:**
  ```python
  # ✅ DO: Implement cleanup() for proper resource disposal
  class MyTaskService:
      def cleanup(self):
          """Priority 1: ServiceLocator calls this first"""
          self._releaseResources()
      
      def close(self):
          """Priority 2: Called if cleanup() doesn't exist"""
          self._releaseResources()
      
      def dispose(self):
          """Priority 3: Called if neither cleanup() nor close() exist"""
          self._releaseResources()
  ```

---

## **Network Manager Integration**

### **Internal Network Calls (UI Thread)**

- **Use NetworkManager for UI-driven network requests:**
  - User-initiated actions (button clicks, form submissions)
  - Loading data for UI display
  - Interactive API calls

- **Access NetworkManager:**
  ```python
  # ✅ DO: Use NetworkManager for internal calls
  from PySide6.QtNetwork import QNetworkRequest
  from PySide6.QtCore import QUrl
  
  ctx = QtAppContext.globalInstance()
  network = ctx.network  # Returns QNetworkAccessManager
  
  if network:
      request = QNetworkRequest(QUrl("https://api.example.com/data"))
      reply = network.get(request)
      reply.finished.connect(lambda: self._handleResponse(reply))
  ```

- **Check if NetworkManager is enabled:**
  ```python
  # ✅ DO: Check feature flag before using
  if ctx.isFeatureEnabled('network'):
      network = ctx.network
      # Use network manager
  else:
      logger.warning("Network feature is disabled")
  ```

### **Automation Network Calls (Background Threads)**

- **Use dedicated HTTP libraries for automation tasks:**
  - Selenium/Playwright for browser automation
  - `requests` or `httpx` for API calls in background threads
  - `aiohttp` for async automation

- **Do NOT use NetworkManager in automation threads:**
  ```python
  # ✅ DO: Use requests in automation tasks
  import requests
  
  class AutomationTask(BaseTask):
      def execute(self):
          # This runs in a background thread
          response = requests.get("https://api.example.com/data")
          data = response.json()
  ```

  ```python
  # ❌ DON'T: Use NetworkManager in background threads
  class AutomationTask(BaseTask):
      def execute(self):
          ctx = QtAppContext.globalInstance()
          network = ctx.network  # Wrong! This is for UI thread only
          # This will cause thread safety issues
  ```

### **Network Call Decision Tree**

```
Is this a network call?
│
├─ YES → Is it triggered by user interaction (UI thread)?
│        │
│        ├─ YES → Use NetworkManager (ctx.network)
│        │        Example: Loading profile data on button click
│        │
│        └─ NO → Is it part of automation/background task?
│                 │
│                 └─ YES → Use requests/httpx/aiohttp
│                          Example: Scraping data in background thread
│
└─ NO → Continue with normal logic
```

### **Examples**

**Internal Network Call (UI Thread):**
```python
# ✅ DO: User clicks "Load Data" button
class MainController:
    def onLoadButtonClicked(self):
        ctx = QtAppContext.globalInstance()
        network = ctx.network
        
        request = QNetworkRequest(QUrl("https://api.example.com/profile"))
        reply = network.get(request)
        reply.finished.connect(self._onProfileLoaded)
    
    def _onProfileLoaded(self, reply):
        data = reply.readAll()
        # Update UI with data
```

**Automation Network Call (Background Thread):**
```python
# ✅ DO: Background task scraping data
import requests

class DataScraperTask(BaseTask):
    def execute(self):
        # This runs in a worker thread
        response = requests.get(
            "https://api.example.com/data",
            headers={"User-Agent": "MyBot/1.0"}
        )
        
        if response.status_code == 200:
            data = response.json()
            self._processData(data)
```

**Browser Automation (Scoped Service):**
```python
# ✅ DO: Browser automation with scoped service
class BrowserAutomationTask(BaseTask):
    def execute(self):
        ctx = QtAppContext.globalInstance()
        taskId = self.uuid
        
        # Browser handles its own network calls
        browser = ChromeBrowserService()
        ctx.registerScopedService(taskId, browser)
        
        try:
            browser.navigate("https://example.com")
            browser.clickElement("#submit")
            # Browser's internal network calls are separate from NetworkManager
        finally:
            ctx.releaseScope(taskId)  # Auto-cleanup browser
```

---

## **Summary Checklist**

- [ ] Use `QtAppContext.globalInstance()` to access all services
- [ ] Register global services for app-wide resources
- [ ] Register scoped services with task UUID for task-specific resources
- [ ] Always call `releaseScope(taskId)` in finally block
- [ ] Implement `cleanup()`/`close()`/`dispose()` in scoped services
- [ ] Use NetworkManager (`ctx.network`) for UI-driven network calls
- [ ] Use `requests`/`httpx`/browser for automation network calls
- [ ] Never use NetworkManager in background threads
- [ ] Check feature flags with `ctx.isFeatureEnabled()` before using optional services