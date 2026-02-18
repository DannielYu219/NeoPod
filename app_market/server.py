#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
应用市场服务器
作用：提供应用列表和下载服务
依赖：Flask, os, json, zipfile
输入：HTTP请求
输出：JSON响应或文件下载
实现：使用Flask框架创建RESTful API，读取apps目录下的应用信息
"""

from flask import Flask, jsonify, send_file, request
import os
import json
import zipfile
import io

app = Flask(__name__)
APP_DIR = os.path.join(os.path.dirname(__file__), 'apps')

# 确保apps目录存在
if not os.path.exists(APP_DIR):
    os.makedirs(APP_DIR)

# 获取应用列表
@app.route('/api/apps', methods=['GET'])
def get_apps():
    """
    获取所有应用信息
    返回格式：
    {
        "apps": [
            {
                "id": "应用ID",
                "name": "应用名称",
                "version": "版本号",
                "description": "应用描述",
                "icon": "图标URL",
                "size": "文件大小",
                "last_updated": "最后更新时间"
            }
        ]
    }
    """
    apps = []
    
    for app_id in os.listdir(APP_DIR):
        app_path = os.path.join(APP_DIR, app_id)
        if not os.path.isdir(app_path):
            continue
        
        # 读取应用信息
        info_path = os.path.join(app_path, 'info.json')
        if not os.path.exists(info_path):
            continue
        
        try:
            with open(info_path, 'r', encoding='utf-8') as f:
                info = json.load(f)
            
            # 计算应用大小
            size = 0
            for root, dirs, files in os.walk(app_path):
                for file in files:
                    file_path = os.path.join(root, file)
                    size += os.path.getsize(file_path)
            
            app_info = {
                "id": app_id,
                "name": info.get('name', app_id),
                "version": info.get('version', '1.0.0'),
                "description": info.get('description', ''),
                "icon": info.get('icon', ''),
                "size": size,
                "last_updated": info.get('last_updated', '')
            }
            apps.append(app_info)
        except Exception as e:
            print(f"Error reading app {app_id}: {e}")
    
    return jsonify({"apps": apps})

# 获取应用详情
@app.route('/api/apps/<app_id>', methods=['GET'])
def get_app_detail(app_id):
    """
    获取单个应用详情
    """
    app_path = os.path.join(APP_DIR, app_id)
    if not os.path.isdir(app_path):
        return jsonify({"error": "App not found"}), 404
    
    info_path = os.path.join(app_path, 'info.json')
    if not os.path.exists(info_path):
        return jsonify({"error": "App info not found"}), 404
    
    try:
        with open(info_path, 'r', encoding='utf-8') as f:
            info = json.load(f)
        
        # 计算应用大小
        size = 0
        for root, dirs, files in os.walk(app_path):
            for file in files:
                file_path = os.path.join(root, file)
                size += os.path.getsize(file_path)
        
        app_info = {
            "id": app_id,
            "name": info.get('name', app_id),
            "version": info.get('version', '1.0.0'),
            "description": info.get('description', ''),
            "icon": info.get('icon', ''),
            "size": size,
            "last_updated": info.get('last_updated', ''),
            "files": []
        }
        
        # 列出应用文件
        for root, dirs, files in os.walk(app_path):
            for file in files:
                relative_path = os.path.relpath(os.path.join(root, file), app_path)
                app_info["files"].append(relative_path)
        
        return jsonify(app_info)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# 下载应用
@app.route('/api/apps/<app_id>/download', methods=['GET'])
def download_app(app_id):
    """
    下载应用（ZIP格式）
    """
    app_path = os.path.join(APP_DIR, app_id)
    if not os.path.isdir(app_path):
        return jsonify({"error": "App not found"}), 404
    
    try:
        # 创建内存中的ZIP文件
        memory_file = io.BytesIO()
        
        with zipfile.ZipFile(memory_file, 'w', zipfile.ZIP_DEFLATED) as zf:
            for root, dirs, files in os.walk(app_path):
                for file in files:
                    file_path = os.path.join(root, file)
                    relative_path = os.path.relpath(file_path, app_path)
                    zf.write(file_path, relative_path)
        
        memory_file.seek(0)
        return send_file(
            memory_file,
            as_attachment=True,
            download_name=f"{app_id}.zip",
            mimetype='application/zip'
        )
    except Exception as e:
        return jsonify({"error": str(e)}), 500

# 健康检查
@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({"status": "ok"})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000, debug=True)
