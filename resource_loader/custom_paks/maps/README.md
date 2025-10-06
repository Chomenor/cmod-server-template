Place custom map pk3s in this folder to be included in the export process and made available on the server. This is intended for situations like map development where it might be necessary to run maps that are not included in the main map manifest.

Notes:

- Place maps directly in this folder, e.g. "maps/mapname.pk3" not "maps/baseEF/mapname.pk3". The baseEF prefix will be added automatically.
- Run the export after adding or modifying maps, e.g. "python3 resource_loader/run_export.py", to make maps available to the server.
- This is not intended to handle large numbers (hundreds or thousands) of maps, as it will make the export slow and inefficient. Use the regular map manifest when possible.
- If you have map(s) that you would like to have added to the repository so other servers can use it, send it to chomenor@gmail.com, or open a GitHub issue. Thanks!
