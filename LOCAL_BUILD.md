这个仓库没有生成 DMG 的脚本。官方发布产物是公证过的 `AltTab.app` 打成 zip，见 `scripts/package_and_notarize_release.sh`，CI 把它作为 GitHub Release 附件上传。

## 本地能直接跑的

一键编译并装进「应用程序」（补 `config/local.xcconfig` 里的版本号、Debug 构建、退出正在运行的 AltTab、删掉旧包再整包拷入，然后打开）：

```bash
ai/install.sh
```

`config/local.xcconfig` 是 gitignore 的。没有 `CURRENT_PROJECT_VERSION` 时，`CFBundleVersion` 不会写进包里，启动时会在 `App.swift` 强制解包处直接退出。往已经存在的 `/Applications/AltTab.app` 里 `cp -R` 也会在框架文件上报 `Operation not permitted`，所以脚本是先 `rm -rf` 再 `ditto`。

第一次打开要在系统设置里授予辅助功能和屏幕录制权限。

## 为什么不要走 Release 脚本

`scripts/build_app.sh` 用的是 Release scheme，签名身份写死在 `config/release.xcconfig` 里：

```
CODE_SIGN_IDENTITY = Developer ID Application: Louis Pontoise (QXD7GW8FHY)
```

你机器上没有这张证书，Release 构建会在签名阶段失败。后面的公证步骤还需要作者的 Apple ID、Team ID 和公证密码，本地跑不了。

## 自己包一个 DMG

仓库里没有这一步，但 Debug 的 `.app` 可以用系统自带的 `hdiutil` 包成 DMG，方便自己拷贝：

```bash
hdiutil create -volname AltTab -srcfolder DerivedData/Build/Products/Debug/AltTab.app -ov -format UDZO AltTab.dmg
```

这是自签名的本地包，打开时系统会提示来源不明，只适合你自己用。