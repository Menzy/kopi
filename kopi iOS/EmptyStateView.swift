//
//  EmptyStateView.swift
//  kopi ios
//
//  Created by Wan Menzy on 20/06/2025.
//

import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack {
            Spacer()
            
            Text("No clipboard history")
                .font(.title2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    EmptyStateView()
}