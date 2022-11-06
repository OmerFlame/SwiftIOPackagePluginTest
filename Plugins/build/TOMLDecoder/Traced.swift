//
//  File.swift
//  
//
//  Created by Omer Shamai on 03/11/2022.
//

struct Traced<Value: Equatable>: Equatable {
    let value: Value
    let index: Substring.Index
}
