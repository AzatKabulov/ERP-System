ERP system - test package
=========================

Windows:  double-click START.bat
Mac:      double-click START.command  (first time: right-click it > Open)

Wait a few minutes the first time (it downloads what it needs, once). When the window says
"Running", it shows:
  - the address to open on this computer (http://localhost:8000)
  - the address for a phone or tablet on the SAME Wi-Fi: open it, install the app, then in the
    app tap Server > Change and type the same address
  - a password (shown once: write it down). Users: owner, manager, sales, warehouse.

To stop: close the window (or press Ctrl+C). Start again with the same file: your data stays
in the folder "local-data". To start from nothing, stop it and delete that folder.

Windows may ask whether the program may use the network: allow it on private networks.
For testing only. Details: scripts/local/ and docs/LOCAL_TEST.md in the project.
