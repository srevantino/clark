# A-SYS

**Developed & managed by Advance Systems 4042.**

A-SYS is a Windows utility for streamlined *installs*, *tweaks*, *config* fixes, and *updates*. It incorporates material derived from the open-source [WinUtil](https://github.com/ChrisTitusTech/winutil) project; use of **this** distribution is **not** open source—see [LICENSE](LICENSE).

## Usage

A-SYS must be run **as Administrator** because it performs system-wide changes.

### Launch (your hosted script)

Use the install URL provided by Advance Systems 4042, for example:

```ps1
irm 'https://myutil.advancesystems4042.com/?token=YOUR_TOKEN' | iex
```

Replace with your current deployment URL and credentials as supplied by your organization.

### Build from source

```ps1
.\Compile.ps1
```

This produces `asys.ps1` in the repository root. Run that script elevated to start the GUI.

## Documentation

Upstream WinUtil documentation may still be helpful for behavior that was not rebranded in code comments: [winutil.christitus.com](https://winutil.christitus.com/).

## License

**Proprietary.** Use is restricted to Advance Systems 4042 staff, companies Advance Systems has permitted in writing, and other parties only with **written authorization** and **payment** as required by Advance Systems 4042. See [LICENSE](LICENSE). Third-party components may remain under their original licenses (see section 6 of the LICENSE file).
