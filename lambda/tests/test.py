import boto3
from moto import mock_dynamodb
import pytest
import src.app as app

@pytest.fixture
def lambda_environment():
    table_name = "kylewilliams-dev-stats"
    return table_name


@pytest.fixture
def data_table():
    with mock_dynamodb():
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.create_table(
            TableName = "kylewilliams-dev-stats",
            KeySchema = [
                {"AttributeName": "stats", "KeyType": "HASH"}],
            AttributeDefinitions = [
                {"AttributeName": "stats", "AttributeType": "S"}],
            BillingMode = "PAY_PER_REQUEST"
            )
        )
        
        yield table


@pytest.fixture
def put_data(data_table, lambda_environment):
    with mock_dynamodb():
        client = boto3.client("dynamodb")
        client.put_item(
            TableName=lambda_environment,
            Item={
                    "stats": "viewCount",
                    "viewCount": 1
                }
        )
def test_record_

app.lambda_handler({}, {}, lambda_environment)

# def test_get_count(lambda_environment, data_table):
#     table_name = "kylewilliams-dev-stats"
#     response = app.lambda_handler({}, {}, table_name=table_name)




# @mock_dynamodb
# def test_get_count():
#     """Test retrieving visitor count from db"""
#     dynamodb = boto3.resource('dynamodb')
#     table_name = app.table_name
#     table = dynamodb.create_table(TableName = table_name,
#                                     KeySchema = [
#                                         {"AttributeName": "stats", "KeyType": "HASH"}],
#                                     AttributeDefinitsions = [
#                                         {"AttributeName": "stats", "AttributeType": "S"}
#                                     ]
#                                   )
#     data = {"stats": "1"}
#     print(app.lambda_handler(table_name=table_name))

# test_get_count()