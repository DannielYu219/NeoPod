# 应用市场API使用范例

## 服务器信息
- 服务器地址：http://localhost:8000
- API 版本：v1

## API 端点

### 1. 获取应用列表
**请求**
```
GET /api/apps
```

**响应**
```json
{
  "apps": [
    {
      "id": "counter_app",
      "name": "计数器应用",
      "version": "1.0.0",
      "description": "一个简单的计数器应用",
      "icon": "icon.png",
      "size": 12345,
      "last_updated": "2026-02-18"
    },
    {
      "id": "color_app",
      "name": "颜色应用",
      "version": "1.0.0",
      "description": "一个简单的颜色选择器应用",
      "icon": "icon.png",
      "size": 67890,
      "last_updated": "2026-02-18"
    }
  ]
}
```

### 2. 获取应用详情
**请求**
```
GET /api/apps/{app_id}
```

**示例**
```
GET /api/apps/counter_app
```

**响应**
```json
{
  "id": "counter_app",
  "name": "计数器应用",
  "version": "1.0.0",
  "description": "一个简单的计数器应用",
  "icon": "icon.png",
  "size": 12345,
  "last_updated": "2026-02-18",
  "files": [
    "info.json",
    "index.html"
  ]
}
```

### 3. 下载应用
**请求**
```
GET /api/apps/{app_id}/download
```

**示例**
```
GET /api/apps/counter_app/download
```

**响应**
- 返回ZIP格式的应用文件
- 文件名：{app_id}.zip

### 4. 健康检查
**请求**
```
GET /health
```

**响应**
```json
{
  "status": "ok"
}
```

## 客户端使用示例

### JavaScript 示例
```javascript
// 获取应用列表
async function getApps() {
  try {
    const response = await fetch('http://localhost:8000/api/apps');
    const data = await response.json();
    console.log('应用列表:', data.apps);
    return data.apps;
  } catch (error) {
    console.error('获取应用列表失败:', error);
  }
}

// 下载应用
async function downloadApp(appId) {
  try {
    const response = await fetch(`http://localhost:8000/api/apps/${appId}/download`);
    const blob = await response.blob();
    const url = window.URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${appId}.zip`;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    window.URL.revokeObjectURL(url);
    console.log('应用下载成功');
  } catch (error) {
    console.error('下载应用失败:', error);
  }
}

// 示例用法
getApps().then(apps => {
  if (apps && apps.length > 0) {
    console.log('第一个应用:', apps[0]);
    // 下载第一个应用
    // downloadApp(apps[0].id);
  }
});
```

### Python 示例
```python
import requests
import zipfile
import io

# 获取应用列表
def get_apps():
    response = requests.get('http://localhost:8000/api/apps')
    if response.status_code == 200:
        data = response.json()
        print('应用列表:', data['apps'])
        return data['apps']
    else:
        print('获取应用列表失败:', response.status_code)

# 下载应用
def download_app(app_id):
    response = requests.get(f'http://localhost:8000/api/apps/{app_id}/download')
    if response.status_code == 200:
        zip_file = zipfile.ZipFile(io.BytesIO(response.content))
        # 解压到当前目录
        zip_file.extractall(f'./{app_id}')
        print('应用下载并解压成功')
    else:
        print('下载应用失败:', response.status_code)

# 示例用法
apps = get_apps()
if apps:
    first_app = apps[0]
    print('第一个应用:', first_app)
    # 下载第一个应用
    # download_app(first_app['id'])
```

### iOS 客户端示例
```swift
import Foundation

class AppMarketClient {
    let baseURL = "http://localhost:8000"
    
    func getApps(completion: @escaping ([AppInfo]?, Error?) -> Void) {
        guard let url = URL(string: "\(baseURL)/api/apps") else {
            completion(nil, NSError(domain: "AppMarket", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            guard let data = data else {
                completion(nil, NSError(domain: "AppMarket", code: 1, userInfo: [NSLocalizedDescriptionKey: "No data"]))
                return
            }
            
            do {
                let decoder = JSONDecoder()
                let response = try decoder.decode(AppListResponse.self, from: data)
                completion(response.apps, nil)
            } catch {
                completion(nil, error)
            }
        }.resume()
    }
    
    func downloadApp(appId: String, completion: @escaping (URL?, Error?) -> Void) {
        guard let url = URL(string: "\(baseURL)/api/apps/\(appId)/download") else {
            completion(nil, NSError(domain: "AppMarket", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"]))
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(nil, error)
                return
            }
            
            guard let data = data else {
                completion(nil, NSError(domain: "AppMarket", code: 1, userInfo: [NSLocalizedDescriptionKey: "No data"]))
                return
            }
            
            // 保存到临时文件
            let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(appId).zip")
            do {
                try data.write(to: tempURL)
                completion(tempURL, nil)
            } catch {
                completion(nil, error)
            }
        }.resume()
    }
}

// 数据模型
struct AppListResponse: Codable {
    let apps: [AppInfo]
}

struct AppInfo: Codable {
    let id: String
    let name: String
    let version: String
    let description: String
    let icon: String
    let size: Int
    let last_updated: String
}

// 示例用法
let client = AppMarketClient()
client.getApps { apps, error in
    if let error = error {
        print("获取应用列表失败:", error)
        return
    }
    
    if let apps = apps {
        print("应用列表:", apps)
        if let firstApp = apps.first {
            print("第一个应用:", firstApp)
            // 下载应用
            /*
            client.downloadApp(appId: firstApp.id) { url, error in
                if let error = error {
                    print("下载应用失败:", error)
                } else if let url = url {
                    print("应用下载成功:", url)
                    // 处理ZIP文件
                }
            }
            */
        }
    }
}
```

## 应用结构规范

### 应用目录结构
```
apps/
├── counter_app/
│   ├── info.json          # 应用信息
│   ├── index.html         # 主页面
│   └── icon.png           # 应用图标（可选）
├── color_app/
│   ├── info.json
│   ├── index.html
│   └── icon.png
└── todo_app/
    ├── info.json
    ├── index.html
    └── icon.png
```

### info.json 格式
```json
{
  "name": "应用名称",
  "version": "1.0.0",
  "description": "应用描述",
  "author": "作者名称",
  "last_updated": "2026-02-18",
  "icon": "icon.png",
  "main_file": "index.html"
}
```

## 服务器部署说明

### 安装依赖
```bash
# 在app_market目录中执行
pip install flask
```

### 启动服务器
```bash
# 在app_market目录中执行
python server.py
```

### 服务器配置
- 主机：0.0.0.0（允许所有IP访问）
- 端口：8000
- 调试模式：开启

### 安全提示
- 本服务器仅用于开发和测试环境
- 生产环境部署时应关闭调试模式
- 建议使用HTTPS和适当的身份验证
