//
//  EmptyStateView.swift
//  kopi ios
//
//  Created by Wan Menzy on 20/06/2025.
//

import SwiftUI

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Clipboard History")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Copy something on your Mac to see it appear here automatically.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}

#Preview {
    EmptyStateView()
} 