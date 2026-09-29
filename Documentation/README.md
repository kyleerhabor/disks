# Doumentation

## Downloading

```sh
git clone https://github.com/kyleerhabor/disks.git Disks
```

## Signing

Disks expects release builds to be signed with a [Developer ID certificate](https://developer.apple.com/help/account/certificates/create-developer-id-certificates). While you can sign with a free account, the provisioning profile will expire after a week, causing the app to fail to launch. Because the app manages passwords, it's not recommended to circumvent this by, say, using an ad-hoc signature.

## CI/CD

Disks uses GitHub Actions for CI/CD. The workflow expects variables and secrets to be set in the repository settings.

| Name                              | Type     | Value                                                        |
| --------------------------------- | -------- | ------------------------------------------------------------ |
| ASC_ISSUER_ID                     | Variable | App Store Connect API Issuer ID                              |
| ASC_KEY_ID                        | Variable | App Store Connect API Key ID                                 |
| ASC_KEY_P8                        | Secret   | Base64-encoded App Store Connect API Key                     |
| DEVELOPER_ID_P12                  | Secret   | Base64-encoded Developer ID Application certificate          |
| DEVELOPER_ID_P12_PASSWORD         | Secret   | Developer ID Application certificate password                |
| DEVELOPER_ID_PROVISIONING_PROFILE | Variable | Base64-encoded Developer ID Application provisioning profile |

You can generate Base64-encoded values from files and copy them to your clipboard with `openssl`:

```sh
openssl base64 -A -in [...] | pbcopy
```

See [App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api) and [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/certificates/list).
