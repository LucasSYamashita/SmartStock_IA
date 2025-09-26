part of 'example.dart';

class ListUserReviewsVariablesBuilder {
  
  final FirebaseDataConnect _dataConnect;
  ListUserReviewsVariablesBuilder(this._dataConnect, );
  Deserializer<ListUserReviewsData> dataDeserializer = (dynamic json)  => ListUserReviewsData.fromJson(jsonDecode(json));
  
  Future<QueryResult<ListUserReviewsData, void>> execute() {
    return ref().execute();
  }

  QueryRef<ListUserReviewsData, void> ref() {
    
    return _dataConnect.query("ListUserReviews", dataDeserializer, emptySerializer, null);
  }
}

class ListUserReviewsUser {
  String id;
  String username;
  List<ListUserReviewsUserReviews> reviews;
  ListUserReviewsUser.fromJson(dynamic json):
  
  id = nativeFromJson<String>(json['id']),
  username = nativeFromJson<String>(json['username']),
  reviews = (json['reviews'] as List<dynamic>)
        .map((e) => ListUserReviewsUserReviews.fromJson(e))
        .toList();

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['id'] = nativeToJson<String>(id);
    json['username'] = nativeToJson<String>(username);
    json['reviews'] = reviews.map((e) => e.toJson()).toList();
    return json;
  }

  ListUserReviewsUser({
    required this.id,
    required this.username,
    required this.reviews,
  });
}

class ListUserReviewsUserReviews {
  int? rating;
  DateTime reviewDate;
  String? reviewText;
  ListUserReviewsUserReviewsMovie movie;
  ListUserReviewsUserReviews.fromJson(dynamic json):
  
  rating = json['rating'] == null ? null : nativeFromJson<int>(json['rating']),
  reviewDate = nativeFromJson<DateTime>(json['reviewDate']),
  reviewText = json['reviewText'] == null ? null : nativeFromJson<String>(json['reviewText']),
  movie = ListUserReviewsUserReviewsMovie.fromJson(json['movie']);

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    if (rating != null) {
      json['rating'] = nativeToJson<int?>(rating);
    }
    json['reviewDate'] = nativeToJson<DateTime>(reviewDate);
    if (reviewText != null) {
      json['reviewText'] = nativeToJson<String?>(reviewText);
    }
    json['movie'] = movie.toJson();
    return json;
  }

  ListUserReviewsUserReviews({
    this.rating,
    required this.reviewDate,
    this.reviewText,
    required this.movie,
  });
}

class ListUserReviewsUserReviewsMovie {
  String id;
  String title;
  ListUserReviewsUserReviewsMovie.fromJson(dynamic json):
  
  id = nativeFromJson<String>(json['id']),
  title = nativeFromJson<String>(json['title']);

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    json['id'] = nativeToJson<String>(id);
    json['title'] = nativeToJson<String>(title);
    return json;
  }

  ListUserReviewsUserReviewsMovie({
    required this.id,
    required this.title,
  });
}

class ListUserReviewsData {
  ListUserReviewsUser? user;
  ListUserReviewsData.fromJson(dynamic json):
  
  user = json['user'] == null ? null : ListUserReviewsUser.fromJson(json['user']);

  Map<String, dynamic> toJson() {
    Map<String, dynamic> json = {};
    if (user != null) {
      json['user'] = user!.toJson();
    }
    return json;
  }

  ListUserReviewsData({
    this.user,
  });
}

