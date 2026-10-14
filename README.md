# Trends in Reported Industrial Greenhouse Gas Emissions, 2010-2023

An R analysis of EPA Greenhouse Gas Reporting Program (GHGRP) data on large direct emitters in the United States.

## Question

How did reported direct emissions change from 2010 to 2023, and how much of that change holds up when only facilities that reported in every year are included?

## Key findings

- Total reported direct emissions fell from about 3.20 to 2.38 billion metric tons CO2e (about -26%) across all reporting facilities, and from about 2.69 to 2.08 billion (about -23%) among the 4,690 facilities that reported in every year. The two samples agree on direction, so changes in which facilities report explain only part of the decline.
- Power plants account for about 94% of the net decline in the balanced sample (about -0.57 of -0.61 billion metric tons CO2e). Every other sector changed by less than 0.02 billion tons.
- Both samples show a dip in 2020 and a partial rebound in 2021.

## Figures

![Total reported direct emissions, 2010-2023](emissions_trend_2010_2023.png)

![Change in emissions by sector, 2010 to 2023](sector_change.png)

![Change in emissions by sector, excluding power plants](sector_change_no_power.png)

Note: the third figure uses a much smaller scale than the second, so bar lengths should only be compared within each figure.

## Data

Source: EPA Greenhouse Gas Reporting Program, [Data Sets page](https://www.epa.gov/ghgreporting/data-sets) ("2023 Data Summary Spreadsheets," zip file).

The data are not included in this repository. To reproduce the analysis:

1. Download and unzip the 2023 Data Summary Spreadsheets.
2. Copy the yearly files (`ghgp_data_2010.xlsx` through `ghgp_data_2023.xlsx`) into `data/raw/`.

The analysis uses the Direct Point Emitters sheet (the first tab) of each yearly file.

## Method

1. **Import:** read the first sheet of each yearly file, skipping the three header rows above the column names, and stacked the years into one table (about 94,000 facility-year rows). Column types are detected from many rows, because the default (1,000 rows) misread sparse columns as TRUE/FALSE and silently turned some real values into missing values.
2. **Checks:** confirmed that every study year is present, that each facility appears at most once per year, and that emissions were read as numbers.
3. **Balanced sample:** kept the 4,690 facilities that reported in every year, to test whether the trend depends on facilities entering or leaving the program.
4. **Sector grouping:** facilities registered under more than one sector are grouped as "Multiple sectors."
5. **Sector labels:** about 9% of balanced-sample facilities change sector label over time. To avoid counting relabeling as an emissions change, each facility keeps its 2010 label throughout.
6. **Summaries and plots:** totals by year for both samples, and change from 2010 to 2023 by sector, using ggplot2.

## How to run

1. Open the project in RStudio (the `.Rproj` file).
2. Install the packages once: `install.packages(c("tidyverse", "readxl", "janitor"))`
3. Put the data in `data/raw/` (see above), then run `ghgp_emissions_analysis.R`. Figures are saved to `figures/`.

Developed with R 4.5.2.

## Limitations

- The GHGRP covers large direct emitters only. These results are **not** total U.S. emissions.
- The balanced sample excludes facilities that started or stopped reporting during the period. Why facilities enter or leave the data cannot be determined from these files.
- About 15% of emissions come from facilities registered under multiple sectors, so sector totals for categories such as refineries (most of which are registered in combinations) are understated.
- Sector results use each facility's 2010 label.
- Changes in program coverage or calculation methods over time were not examined.
- [Add the number of missing emissions values from the missing-emissions check in the script, if any.]
- This is a descriptive analysis. It shows how reported emissions changed, not why.

## Repository contents

- `ghgp_emissions_analysis.R`: full analysis script
- `figures/`: saved plots
- `data/raw/`: where the EPA spreadsheets go (not included)

Author: [Your name]
