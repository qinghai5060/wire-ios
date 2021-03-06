//
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
//

import ZMCDataModel


private extension ZMConversationMessage {

    /// Whether the `Delete for everyone` option should be allowed and shown for this message.
    var canBeDeletedForEveryone: Bool {
        guard let sender = sender, let conversation = conversation else { return false }
        return sender.isSelfUser && conversation.isSelfAnActiveMember
    }

    var deletionConfiguration: DeletionConfiguration {
        // If the message failed to send we only want to show the delete for everyone option,
        // as we can not be sure that it did not hit the backend before we expired it.
        if deliveryState == .failedToSend {
            return .delete
        }

        return canBeDeletedForEveryone ? .hideAndDelete : .hide
    }

}


extension ConversationContentViewController {

    /**
     Presents a `UIAlertController` of type action sheet with the options to delete a message everywhere, locally
     or to cancel. An optional completion block can be provided to get notified when an action has been selected.
     The delete everywhere option is only shown if this action is allowed for the input message.
     
     - parameter message:    The message for which the alert controller should be shown
     */
    func presentDeletionAlertController(forMessage message: ZMConversationMessage, completion: (() -> Void)?) {
        let alert = UIAlertController.forMessageDeletion(with: message.deletionConfiguration) { [weak self] action in
            
            // Tracking needs to be called before performing the action, since the content of the message is cleared
            if case .delete(let type) = action {
                self?.trackDelete(message, deletionType:type)

                ZMUserSession.shared()?.enqueueChanges {
                    switch type {
                    case .local:
                        ZMMessage.hideMessage(message)
                    case .everywhere:
                        ZMMessage.deleteForEveryone(message)
                    }
                }
            }

            completion?()
            self?.dismiss(animated: true, completion: nil)
        }

        if let presentationController = alert.popoverPresentationController,
            let cell = cell(for: message) {
            presentationController.sourceView = cell.selectionView
            presentationController.sourceRect = cell.selectionRect
        }
        present(alert, animated: true, completion: nil)
    }
    
    fileprivate func trackDelete(_ message: ZMConversationMessage, deletionType: AlertAction.DeletionType) {
        let conversationType: ConversationType = (conversation.conversationType == .group) ? .group : .oneToOne
        let messageType = Message.messageType(message)
        let timeElapsed = message.serverTimestamp?.timeIntervalSinceNow ?? 0
        Analytics.shared()?.tagDeletedMessage(messageType, messageDeletionType: deletionType.analyticsType, conversationType:conversationType, timeElapsed: 0 - timeElapsed)
    }

}

private enum AlertAction {
    enum DeletionType {
        case local
        case everywhere
        
        var analyticsType: MessageDeletionType {
            switch self {
            case .local: return .local
            case .everywhere: return .everywhere
            }
        }
    }
    
    case delete(DeletionType), cancel
}

// Used to enforce only valid configurations can be shown.
// Unfortunately this can not be done with an `OptionSetType`
// as there is no way to enforce a non-empty option set.
private enum DeletionConfiguration {
    case hide, delete, hideAndDelete

    var showHide: Bool {
        switch self {
        case .hide, .hideAndDelete: return true
        case .delete: return false
        }
    }

    var showDelete: Bool {
        switch self {
        case .delete, .hideAndDelete: return true
        case .hide: return false
        }
    }
}

private extension UIAlertController {

    static func forMessageDeletion(with configuration: DeletionConfiguration, selectedAction: @escaping (AlertAction) -> Void) -> UIAlertController {
        let alertTitle = "message.delete_dialog.message".localized
        let alert = UIAlertController(title: alertTitle, message: nil, preferredStyle: .actionSheet)

        if configuration.showHide {
            let hideTitle = "message.delete_dialog.action.hide".localized
            let hideAction = UIAlertAction(title: hideTitle, style: .default, handler: { _ in selectedAction(.delete(.local)) })
            alert.addAction(hideAction)
        }

        if configuration.showDelete {
            let deleteTitle = "message.delete_dialog.action.delete".localized
            let deleteForEveryoneAction = UIAlertAction(title: deleteTitle, style: .default, handler: { _ in selectedAction(.delete(.everywhere)) })
            alert.addAction(deleteForEveryoneAction)
        }

        let cancelTitle = "message.delete_dialog.action.cancel".localized
        let cancelAction = UIAlertAction(title: cancelTitle, style: .cancel, handler: { _ in selectedAction(.cancel)})
        alert.addAction(cancelAction)

        return alert
    }

}
