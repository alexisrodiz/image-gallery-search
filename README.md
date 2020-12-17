# Image Gallery Search

Image Gallery Search script allows you to search stored images based on attribute fields. It provides a bunch of methods to get the data that you need in a fastest way. Also, it uses a cache to speed up the searches.

## Content

* [Prerequisites](#Prerequisites)
* [Working with the script](#Working-with-the-script)
  - [General use-case](#General-use-case)
  - [How to run](#How-to-run)
  - [Other flags](#Other-flags)
* [Benchmarking](#Benchmarking)
* [Author](#Author)
* [License](#License)


### Prerequisites

Please keep in mind that **'Pearl(v5.28.1) built for MSWin32-x64-multi-thread'** was used while developing this project.

Next modules are used in script 'image_gallery_search.pl', so you would have to install them via your favourite package manager.

* JSON;
* autodie;
* Pod::Usage qw(pod2usage);
* Getopt::Long qw(GetOptions);
* DBI;
* REST::Client;
* threads;
* Thread::Queue;

### Working with the script

## General use-case

```
perl image_gallery_search [-help|-man] -method [-parameters]
```

## How to run

Next command line will run the script having the value of the 'method' argument as a name of the method which should be executed.

```
perl image_gallery_search -method=get_images
```


## Run the script with the page parameter

Fetching the data manually passing the page number as parameter

```
perl image_gallery_search -method=get_images -page=n
```

## Other flags

-search_param : Parameter to search

-page : The numbe of page to fetch (use it with get_image method)

-auth : Request new token


**On average, it takes ~20 sec to update the local cache.**

## Author

* **Juan Alexis Rodiz** - *2020*

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details
