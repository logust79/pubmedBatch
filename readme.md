# pubmedBatch

## What it does
* Search gene terms associated with phenotypes **in batch** on Pubmed. The gene terms shall be grouped in a column in a csv file. 
* In order to speed up the query, and to reduce the Pubmed query frequency, the app saves each unique searches in its SQLite database for 14 days (which can be changed. See **Installation**).

## Installation
* To install, run `install_dependent.sh` first (only work on Linux-based systems)
* If you run into `make` problem, you might need to install `make` first, by `sudo apt-get install build-essential`.
* To change the life time of a query search, go to *config.yml* and change the value of `life` in seconds.
* For multiple workers, please use `starman`: `starman --workers 10 -p 3000 -a bin/app.psgi`.
* Port default is 5000. You can change it in `bin/app.psgi`, `set port => 8080`. Not relevant if you use `starman`.
* After running, you can open your browser and visit the page by `localhost:5000/batch_pubmed`.
* Note that relevant data will be saved / fetched according to the username. The data are saved in `batch_pubmed_result/username`.
* You can use the files in `testfiles` to play with it.

**NOTE** Please follow NCBI policies. Try to avoid massive queries during States's busy times. Early mornings and weekends are good times for massive queries.

## Caveat

* Searched result is automated saved under the `username`'s folder.
* `del row` will delete row on the displayed data, but will not delete it from your file. So reloading the file will revive the deleted row. I can make it to delete the data permanently though.
* You need to refresh the page to find any recently saved data in the left column.
* Pubmed doesn't want to be harassed too frequently in busy times, so try to use it for massive queries in US night times and weekends.

## Future work

