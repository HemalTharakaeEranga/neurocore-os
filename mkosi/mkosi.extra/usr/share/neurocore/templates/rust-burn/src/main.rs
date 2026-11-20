// SPDX-FileCopyrightText: 2026 NeuroCore OS Contributors
// SPDX-License-Identifier: MIT OR Apache-2.0

use burn::backend::NdArray;
use burn::tensor::Tensor;

type Backend = NdArray<f32>;

fn main() {
    let device = Default::default();
    let a = Tensor::<Backend, 2>::from_floats([[1.0, 2.0], [3.0, 4.0]], &device);
    let b = Tensor::<Backend, 2>::from_floats([[2.0, 0.0], [1.0, 2.0]], &device);
    let c = a.matmul(b);
    println!("NeuroCore Burn matmul output:\n{}", c);
}
