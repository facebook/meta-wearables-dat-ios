# Meta Wearables Device Access Toolkit for iOS

[![Swift Package](https://img.shields.io/badge/Swift_Package-0.2.1-brightgreen?logo=swift&logoColor=white)](https://github.com/facebook/meta-wearables-dat-ios/tags)
[![Docs](https://img.shields.io/badge/API_Reference-0.2-blue?logo=meta)](https://wearables.developer.meta.com/docs/reference/ios_swift/dat/0.2)

The Meta Wearables Device Access Toolkit enables developers to utilize Meta's AI glasses to build hands-free wearable experiences into their mobile applications.
By integrating this SDK, developers can reliably connect to Meta's AI glasses and leverage capabilities like video streaming and photo capture.

The Wearables Device Access Toolkit is in developer preview.
Developers can access our SDK and documentation, test on supported AI glasses, and create organizations and release channels to share with test users.

## Documentation & Community

Find our full [developer documentation](https://wearables.developer.meta.com/docs/develop/) on the Wearables Developer Center.

You can find an overview of the Wearables Developer Center [here](https://wearables.developer.meta.com/).
Create an account to stay informed of all updates, report bugs and register your organization.
Set up a project and release channel to share your integration with test users.

For help, discussion about best practices or to suggest feature ideas visit our [discussions forum](https://github.com/facebook/meta-wearables-dat-ios/discussions).

See the [changelog](CHANGELOG.md) for the latest updates.

## Including the SDK in your project

The easiest way to add the SDK to your project is by using Swift Package Manager.

1. In Xcode, select **File** > **Add Package Dependencies...**
1. Search for `https://github.com/facebook/meta-wearables-dat-ios` in the top right corner
1. Select `meta-wearables-dat-ios`
1. Set the version to one of the [available versions](https://github.com/facebook/meta-wearables-dat-ios/tags)
1. Click **Add Package**
1. Select the target to which you want to add the packages
1. Click **Add Package**

## Developer Terms

- By using the Wearables Device Access Toolkit, you agree to our [Meta Wearables Developer Terms](https://wearables.developer.meta.com/terms),
  including our [Acceptable Use Policy](https://wearables.developer.meta.com/acceptable-use-policy).
- By enabling Meta integrations, including through this SDK, Meta may collect information about how users' Meta devices communicate with your app.
  Meta will use this information collected in accordance with our [Privacy Policy](https://www.meta.com/legal/privacy-policy/).
- You may limit Meta's access to data from users' devices by following the instructions below.

### Opting out of data collection

To configure analytics settings in your Meta Wearables DAT iOS app, you can modify your app's `Info.plist` file using either of these two methods:

**Method 1:** Using Xcode (Recommended)

1. In Xcode, select your app target in the **Project** navigator
1. Go to the **Info** tab
1. Navigate to **Custom iOS Target Properties**  and find the `MWDAT` key
1. Add a new key under `MWDAT` called `Analytics` of type `Dictionary`
1. Add a new key to the `Analytics` dictionary called `OptOut` of type `Boolean` and set the value to `YES`

**Method 2:** Direct XML editing

Add or modify the following in your `Info.plist` file.

```XML
<key>MWDAT</key>
<dict>
    <key>Analytics</key>
    <dict>
        <key>OptOut</key>
        <true/>
    </dict>
</dict>
```

**Default behavior:** If the `OptOut` key is missing or set to `NO`/`<false/>`, analytics are enabled
(i.e., you are **not** opting out). Set to `YES`/`<true/>` to disable data collection.

**Note:** In other words, this setting controls whether or not you're opting out of analytics:

- `YES`/`<true/>` = Opt out (analytics **disabled**)
- `NO`/`<false/>` = Opt in (analytics **enabled**)

## License

See the [LICENSE](LICENSE) file.
