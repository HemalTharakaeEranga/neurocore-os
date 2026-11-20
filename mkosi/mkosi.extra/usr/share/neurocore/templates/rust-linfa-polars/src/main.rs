// SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

use polars::prelude::*;

fn main() -> PolarsResult<()> {
    let path = "/usr/share/neurocore/datasets/synthetic-tabular/neurocore_tabular_v1.csv";
    let df = CsvReadOptions::default()
        .try_into_reader_with_file_path(Some(path.into()))?
        .finish()?;
    println!("Loaded NeuroCore synthetic tabular dataset: shape={:?}", df.shape());
    println!("{}", df.head(Some(5)));
    Ok(())
}
