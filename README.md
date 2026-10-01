# ClaudeChat

iOS 聊天 App，接入 Anthropic 格式（`/v1/messages`）的中转站 API。

- 流式输出，支持 Markdown 渲染和代码高亮
- 多对话管理：新建、重命名、删除、搜索
- 多模型切换，可设置新对话默认模型
- 支持上传图片、PDF 和文本文件
- 通过 WebDAV（比如坚果云）在多台设备间同步对话

## 编译

推送到 GitHub 后，Actions 会自动在云端 Mac 上编译，生成未签名的 `ClaudeChat.ipa`，并发布到仓库的 Releases 页面。

## 安装

在 iPhone 上用 Safari 打开 Releases 页面下载 ipa，用"共享 → SideStore"打开，或者在 SideStore 的 My Apps 里点 "+" 选择这个 ipa。
