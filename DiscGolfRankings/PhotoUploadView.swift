import SwiftUI
import PhotosUI
import UIKit

// MARK: - PhotoUploadAvatar
// Reusable circular upload control. Tap it → PhotosPicker → compress → upload to
// Firebase Storage → call onUploaded(url) so the parent can save the URL.

struct PhotoUploadAvatar: View {
    /// Storage path to write to, e.g. "users/abc123/profile.jpg" or "clubs/xyz/logo.jpg"
    let storagePath: String
    /// Currently-displayed image URL (or empty string if not set). Updated on success.
    @Binding var photoURL: String
    /// Two-letter initials used as fallback when no image is set
    let initials: String
    /// Size of the circle
    var diameter: CGFloat = 96

    @State private var selectedItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var errorMsg:    String?

    private let service = FirebaseService.shared

    var body: some View {
        VStack(spacing: 8) {
            PhotosPicker(selection: $selectedItem,
                         matching: .images,
                         photoLibrary: .shared()) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Theme.accent, Theme.gold],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: diameter, height: diameter)

                    if let url = URL(string: photoURL), !photoURL.isEmpty {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:    ProgressView().tint(.white)
                            case .success(let img): img.resizable().scaledToFill()
                            case .failure:  Image(systemName: "photo.badge.exclamationmark")
                                                .font(.system(size: 32)).foregroundStyle(.white)
                            @unknown default: EmptyView()
                            }
                        }
                        .frame(width: diameter - 4, height: diameter - 4)
                        .clipShape(Circle())
                    } else {
                        Text(initials)
                            .font(.system(size: diameter * 0.36, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    // Upload spinner overlay
                    if isUploading {
                        Circle()
                            .fill(.black.opacity(0.45))
                            .frame(width: diameter, height: diameter)
                        ProgressView().tint(.white)
                    }

                    // Camera badge (lower-right)
                    if !isUploading {
                        Image(systemName: "camera.fill")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(Theme.accent, in: Circle())
                            .overlay(Circle().stroke(Theme.background, lineWidth: 3))
                            .offset(x: diameter * 0.32, y: diameter * 0.32)
                    }
                }
                .shadow(color: Theme.accent.opacity(0.4), radius: 12)
            }
            .disabled(isUploading)

            Text(isUploading ? "Uploading…" : "Tap to change photo")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)

            if let errorMsg {
                Text(errorMsg).font(.caption2).foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .onChange(of: selectedItem) { _, newItem in
            guard let item = newItem else { return }
            Task { await handlePicked(item) }
        }
    }

    // MARK: Pipeline

    private func handlePicked(_ item: PhotosPickerItem) async {
        errorMsg = nil
        isUploading = true
        defer { isUploading = false }

        // 1. Pull the raw data from the picker
        guard let rawData = try? await item.loadTransferable(type: Data.self) else {
            errorMsg = "Couldn't read that image."
            return
        }
        // 2. Compress/resize to keep upload small and fast
        guard let jpeg = Self.compressedJPEG(from: rawData) else {
            errorMsg = "Unsupported image format."
            return
        }
        // 3. Upload to Firebase Storage and grab the public download URL
        do {
            let url = try await service.uploadImage(jpeg, path: storagePath)
            photoURL = url
        } catch {
            let ns = error as NSError
            // Surface specific Firebase Storage error codes so debugging is easier.
            // -13010 objectNotFound | -13013 unauthorized | -13020 unauthenticated
            // -13021 retryLimitExceeded | -13030 bucketNotFound
            switch ns.code {
            case -13013, -13021:
                errorMsg = "Storage rules block this upload. Update the rules in Firebase Console."
            case -13020:
                errorMsg = "You're signed out. Sign in and try again."
            case -13030:
                errorMsg = "Storage bucket missing. Enable Storage in Firebase Console."
            default:
                errorMsg = "Upload failed (\(ns.code)): \(error.localizedDescription)"
            }
        }
    }

    /// Downscales to a max 1024px on the long edge and re-encodes as JPEG @ 0.8 quality.
    /// Result is usually 100-400 KB which uploads in a second on 4G.
    static func compressedJPEG(from data: Data,
                               maxDimension: CGFloat = 1024,
                               quality: CGFloat = 0.8) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let longEdge = max(size.width, size.height)
        let scale = longEdge > maxDimension ? maxDimension / longEdge : 1.0
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
