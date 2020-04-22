import 'package:apple_sign_in/apple_sign_in.dart';
import 'package:appsagainsthumanity/data/app_preferences.dart';
import 'package:appsagainsthumanity/data/features/game/model/player.dart';
import 'package:appsagainsthumanity/data/features/users/model/user.dart';
import 'package:appsagainsthumanity/data/firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:logging/logging.dart';

class UserRepository {
    final FirebaseAuth _auth;
    final Firestore _db = Firestore.instance;

    UserRepository({FirebaseAuth firebaseAuth})
        : _auth = firebaseAuth ?? FirebaseAuth.instance;

    Future<bool> isSignedIn() async {
        return (await _auth.currentUser()) != null;
    }

    Future<User> getUser() {
        return currentUserOrThrow((firebaseUser) async {
            var doc = _userDocument(firebaseUser);
            var snapshot = await doc.get();
            return User(
                id: doc.documentID,
                name: snapshot['name'],
                avatarUrl: snapshot['avatarUrl'],
                updatedAt: (snapshot['updatedAt'] as Timestamp).toDate()
            );
        });
    }

    Future<User> signInWithGoogle() async {
        GoogleSignIn _googleSignIn = GoogleSignIn(
            scopes: [
                'email',
                'https://www.googleapis.com/auth/userinfo.profile',
            ],
        );

        try {
            var acct = await _googleSignIn.signIn();
            var auth = await acct.authentication;

            var result = await _auth.signInWithCredential(GoogleAuthProvider.getCredential(
                idToken: auth.idToken,
                accessToken: auth.accessToken
            ));

            return _finishSigningInWithResult(result);
        } catch (error) {
            print(error);
            throw error;
        }
    }

    Future<User> signInWithApple() async {
        final AuthorizationResult result = await AppleSignIn.performRequests([
            AppleIdRequest(requestedScopes: [Scope.email, Scope.fullName])
        ]);

        switch (result.status) {
            case AuthorizationStatus.authorized:
            // Success
                final AppleIdCredential appleIdCredential = result.credential;
                OAuthProvider oAuthProvider = OAuthProvider(providerId: "apple.com");
                final AuthCredential credential = oAuthProvider.getCredential(
                    idToken: String.fromCharCodes(appleIdCredential.identityToken),
                    accessToken: String.fromCharCodes(appleIdCredential.authorizationCode),
                );

                var name = Player.DEFAULT_NAME;
                if (appleIdCredential.fullName != null) {
                    var nameComponents = appleIdCredential.fullName;
                    name = nameComponents.nickname ??
                        "${nameComponents.givenName ?? nameComponents.middleName ?? ""} ${nameComponents.familyName ?? ""}";
                }

                final AuthResult _result = await _auth.signInWithCredential(credential);

                return _finishSigningInWithResult(_result, name: name);
                break;
            case AuthorizationStatus.error:
                throw result.error.localizedFailureReason;
                break;
            case AuthorizationStatus.cancelled:
                print("User Cancelled operation");
                throw 'Cancelled';
                break;
            default:
                throw 'Unable to sign in';
        }
    }

    Future<User> _finishSigningInWithResult(AuthResult result, {String name}) async {
        try {
            if (result.user != null) {
                if (name != null && result.user.displayName != name) {
                    var updateInfo = UserUpdateInfo();
                    updateInfo.displayName = name;
                    await result.user.updateProfile(updateInfo);
                    await result.user.reload();
                    print("Updated user's name to $name");
                }

                // Create the user obj acct in FB
                var userDoc = _userDocument(result.user);

                await userDoc.setData({
                    "name": result.user.displayName,
                    "avatarUrl": result.user.photoUrl,
                    "updatedAt": Timestamp.now()
                }, merge: true);

                Logger("UserRepository").fine(
                    "Signed-in! User(id=${result.user.uid}, name=${result.user.displayName}, photoUrl=${result.user
                        .photoUrl})");

                return User(
                    id: result.user.uid,
                    name: result.user.displayName,
                    avatarUrl: result.user.photoUrl,
                    updatedAt: DateTime.now()
                );
            } else {
                throw result;
            }
        } catch (error) {
            print(error);
            throw error;
        }
    }

    /// Sign-out of the user's account
    Future<void> signOut() async {
        await AppPreferences().clear();
        await _auth.signOut();
    }

    Future<void> deleteAccount() async {
        await AppPreferences().clear();
        var user = await _auth.currentUser();
        await user.delete();
    }

    DocumentReference _userDocument(FirebaseUser user) {
        return _db.collection(FirebaseConstants.COLLECTION_USERS)
            .document(user.uid);
    }
}
