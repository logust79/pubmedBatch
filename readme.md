# pubmedBatch

* To install, run install_dependent.sh first. (only work on Linux-based systems)
* For multiple workers, please use `starman`: `starman --workers 10 -p 3000 -a bin/app.psgi`
* Port default is 5000. You can change it in `bin/app.psgi`, `set port => 8080`. Not relevant if you use `starman`.
* After running, you can open your browser and visit the page by `localhost:5000/batch_pubmed/username`
* Note that relevant data will be saved / fetched according to the username. The data are saved in `batch_pubmed_result/username`.
* You can use the files in `testfiles` to play with it.

**NOTE** Please follow NCBI policies. Try to avoid massive queries during States's busy times. Early mornings and weekends are good times for massive queries.

## Caveat

* Searched result is automated saved under the `username`'s folder.
* You can't change saved file names.
* `del row` will delete row on the displayed data, but will not delete it from your file. So reloading the file will revive the deleted row. I can make it to delete the data permanently though.
* You need to refresh the page to find any recently saved data in the left column.

## Future work

* I will save gene queries for a short term (say 15 days) to speed up and avoid jamming pubmed.
