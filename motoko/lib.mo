import Types "HttpTypes";
import Itertools "mo:itertools/Iter";
import Sha256 "mo:sha2/Sha256";
import Text "mo:base/Text";
import Iter "mo:base/Iter";
import Debug "mo:base/Debug";
import Blob "mo:base/Blob";
import Buffer "mo:base/Buffer";
import Char "mo:base/Char";
import Nat8 "mo:base/Nat8";
import Nat32 "mo:base/Nat32";
import Time "mo:base/Time";
import Int "mo:base/Int";
import BTree "mo:stableheapbtreemap/BTree";

module {
    public func serializeHttpRequest(request: Types.HttpRequestArgs): Blob {
        let method = switch(request.method) {
            case(#get) { "GET" };
            case(#post) { "POST" };
            case(#head) { "HEAD" };
        };
        let headers_list = Iter.map<Types.HttpHeader, Text>(
            request.headers.vals(),
            func ({name: Text; value: Text}) { name # "\t" # value });
        let headers_joined = Itertools.reduce<Text>(headers_list, func(a: Text, b: Text) {a # "\r" # b});
        let ?headers_joined2 = headers_joined else {
            Debug.trap("programming error");
        };
        let header_part = method # "\n" # request.url # "\n" # headers_joined2;

        let body = switch(request.body) {
            case (?body) { body };
            case null { [] };
        };
        let result = Buffer.Buffer<Nat8>(header_part.size() + 1 + body.size());
        result.append(Buffer.fromArray(Blob.toArray(Text.encodeUtf8(header_part))));
        result.add(Nat8.fromNat(Nat32.toNat(Char.toNat32('\n'))));
        result.append(Buffer.fromArray(body));
        Blob.fromArray(Buffer.toArray(result));
    };

    public func hashOfHttpRequest(request: Types.HttpRequestArgs): Blob {
        // TODO: space inefficient
        let blob = serializeHttpRequest(request);
        Sha256.fromBlob(#sha256, blob);
    };

    type HttpRequestsChecker = {
        hashes: BTree.BTree<Blob, Int>; // hash -> time
        times: BTree.BTree<Int, BTree.BTree<Blob, ()>>;
        var timeout: Int;
    };

    private func deleteOldHttpRequests(checker: HttpRequestsChecker) {
        let threshold = Time.now() - checker.timeout;
        label r loop {
            let ?(minTime, hashes) = BTree.min(checker.times) else {
                break r;
            };
            if (minTime > threshold) {
                break r;
            };
            ignore BTree.deleteMin(checker.times, Int.compare);
            for ((hash, _) in BTree.entries(hashes)) {
                ignore BTree.delete(checker.hashes, Blob.compare, hash);
            };
        };
    };

    public func announceHttpRequestHash(checker: HttpRequestsChecker, hash: Blob) {
        deleteOldHttpRequests(checker);
        let now = Time.now();
        ignore BTree.insert<Blob, Int>(checker.hashes, Blob.compare, hash, now);

        // If there is an old hash equal to this, first delete it to clean times:
        switch (BTree.get(checker.hashes, Blob.compare, hash)) {
            case (?time) {
                ignore BTree.delete(checker.hashes, Blob.compare, hash);
                let ?subtree = BTree.get(checker.times, Int.compare, time) else {
                    Debug.trap("programming error")
                };
                if (BTree.size(subtree) == 1) {
                    ignore BTree.delete(checker.times, Int.compare, time)
                } else {
                    ignore BTree.delete(subtree, Blob.compare, hash);
                };
            };
            case null {};
        };

        // Insert into two trees:
        ignore BTree.insert(checker.hashes, Blob.compare, hash, now);
        switch (BTree.get(checker.times, Int.compare, now)) {
            case (?hashes) {
                ignore BTree.insert(hashes, Blob.compare, hash, ());
            };
            case null {
                let subtree = BTree.init<Blob, ()>(null);
                ignore BTree.insert(subtree, Blob.compare, hash, ());
                ignore BTree.insert(checker.times, Int.compare, now, subtree);
            }
        };
    };

    public func announceHttpRequest(checker: HttpRequestsChecker, request: Types.HttpRequestArgs) {
        announceHttpRequestHash(checker, hashOfHttpRequest(request));
    };

    public func checkHttpRequest(checker: HttpRequestsChecker, hash: Blob): Bool {
        BTree.has(checker.hashes, Blob.compare, hash);
    };
};